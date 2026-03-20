package hub

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"github.com/junghan0611/homeagent/internal/config"
	"github.com/junghan0611/homeagent/internal/matter"
)

// --- test helpers ---

// testHub creates a Hub with mock devices, no real matter connection.
// Use for read-only endpoint tests (GET /api/devices, etc).
func testHub(t *testing.T) *Hub {
	t.Helper()
	h := &Hub{
		cfg:        &config.Config{},
		devices:    make(map[int]*DeviceState),
		eventCh:    make(chan Event, 100),
		sseClients: make(map[chan Event]struct{}),
		aliases:    make(map[int]DeviceAlias),
	}
	// Populate mock devices
	h.devices[1] = &DeviceState{
		NodeID:    1,
		Name:      "현관문 센서",
		Room:      "현관",
		Type:      "contact_sensor",
		Available: true,
		State:     map[string]interface{}{"contact": false},
	}
	h.devices[8] = &DeviceState{
		NodeID:    8,
		Name:      "거실 플러그",
		Room:      "거실",
		Type:      "on_off_plug",
		Available: true,
		State:     map[string]interface{}{"on": true},
	}
	return h
}

// testMux registers hub handlers and returns the mux.
func testMux(h *Hub) *http.ServeMux {
	mux := http.NewServeMux()
	h.RegisterHTTP(mux)
	return mux
}

// mockMatterWSServer creates a mock WS server that acts like matterjs-server.
// The handler processes each incoming WS message.
func mockMatterWSServer(t *testing.T, handler func(conn *websocket.Conn, msg map[string]interface{})) *httptest.Server {
	t.Helper()
	upgrader := websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			t.Logf("upgrade error: %v", err)
			return
		}
		defer conn.Close()

		// Send server info
		conn.WriteJSON(matter.ServerInfo{
			FabricID:   1,
			SDKVersion: "test",
		})

		for {
			var msg map[string]interface{}
			if err := conn.ReadJSON(&msg); err != nil {
				return
			}
			handler(conn, msg)
		}
	}))
}

// testHubWithMatter creates a Hub connected to a mock matterjs-server.
// Caller must defer srv.Close(). ReadLoop runs in background.
func testHubWithMatter(t *testing.T, handler func(conn *websocket.Conn, msg map[string]interface{})) (*Hub, *httptest.Server) {
	t.Helper()
	srv := mockMatterWSServer(t, handler)
	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http")

	h := &Hub{
		cfg:        &config.Config{MatterWSURL: wsURL},
		matter:     matter.NewClient(wsURL),
		devices:    make(map[int]*DeviceState),
		eventCh:    make(chan Event, 100),
		sseClients: make(map[chan Event]struct{}),
		aliases:    make(map[int]DeviceAlias),
	}

	// Populate a test device
	h.devices[8] = &DeviceState{
		NodeID: 8, Name: "거실 플러그", Room: "거실",
		Type: "on_off_plug", Available: true,
		State: map[string]interface{}{"on": false},
	}

	// Connect + start read loop
	ctx := context.Background()
	if err := h.matter.Connect(ctx); err != nil {
		t.Fatalf("connect: %v", err)
	}
	go h.matter.ReadLoop(ctx)
	time.Sleep(20 * time.Millisecond) // let read loop start

	return h, srv
}

// --- GET /api/devices ---

func TestAPIGetDevices(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)

	req := httptest.NewRequest("GET", "/api/devices", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != 200 {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var devices []DeviceState
	if err := json.NewDecoder(w.Body).Decode(&devices); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(devices) != 2 {
		t.Fatalf("expected 2 devices, got %d", len(devices))
	}

	// Check content type
	ct := w.Header().Get("Content-Type")
	if ct != "application/json" {
		t.Errorf("expected application/json, got %q", ct)
	}
}

func TestAPIGetDevices_Empty(t *testing.T) {
	h := &Hub{
		cfg:        &config.Config{},
		devices:    make(map[int]*DeviceState),
		eventCh:    make(chan Event, 10),
		sseClients: make(map[chan Event]struct{}),
		aliases:    make(map[int]DeviceAlias),
	}
	mux := testMux(h)

	req := httptest.NewRequest("GET", "/api/devices", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != 200 {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var devices []DeviceState
	json.NewDecoder(w.Body).Decode(&devices)
	if len(devices) != 0 {
		t.Errorf("expected 0 devices, got %d", len(devices))
	}
}

// --- GET /api/devices/:node_id ---

func TestAPIGetDeviceByID(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)

	req := httptest.NewRequest("GET", "/api/devices/8", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != 200 {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var dev DeviceState
	if err := json.NewDecoder(w.Body).Decode(&dev); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if dev.NodeID != 8 {
		t.Errorf("expected node_id 8, got %d", dev.NodeID)
	}
	if dev.Name != "거실 플러그" {
		t.Errorf("expected name '거실 플러그', got %q", dev.Name)
	}
}

func TestAPIGetDeviceByID_NotFound(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)

	req := httptest.NewRequest("GET", "/api/devices/999", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != 404 {
		t.Fatalf("expected 404, got %d", w.Code)
	}
}

func TestAPIGetDeviceByID_InvalidID(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)

	req := httptest.NewRequest("GET", "/api/devices/abc", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != 400 {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

// --- POST /api/devices/command ---

func TestAPICommand_OnOff(t *testing.T) {
	var receivedCmd string
	h, srv := testHubWithMatter(t, func(conn *websocket.Conn, msg map[string]interface{}) {
		if msg["command"] == "device_command" {
			args, _ := msg["args"].(map[string]interface{})
			receivedCmd = args["command_name"].(string)
			conn.WriteJSON(map[string]interface{}{
				"message_id": msg["message_id"],
				"error_code": 0,
			})
		}
	})
	defer srv.Close()
	defer h.matter.Close()

	mux := testMux(h)

	body := `{"node_id": 8, "command": "on"}`
	req := httptest.NewRequest("POST", "/api/devices/command", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp map[string]string
	json.NewDecoder(w.Body).Decode(&resp)
	if resp["status"] != "ok" {
		t.Errorf("expected status ok, got %q", resp["status"])
	}
	if receivedCmd != "on" {
		t.Errorf("expected command_name 'on', got %q", receivedCmd)
	}
}

func TestAPICommand_SetLevel(t *testing.T) {
	var receivedPayload map[string]interface{}
	h, srv := testHubWithMatter(t, func(conn *websocket.Conn, msg map[string]interface{}) {
		if msg["command"] == "device_command" {
			args, _ := msg["args"].(map[string]interface{})
			receivedPayload, _ = args["payload"].(map[string]interface{})
			conn.WriteJSON(map[string]interface{}{
				"message_id": msg["message_id"],
				"error_code": 0,
			})
		}
	})
	defer srv.Close()
	defer h.matter.Close()

	mux := testMux(h)

	body := `{"node_id": 8, "command": "set_level", "level": 128}`
	req := httptest.NewRequest("POST", "/api/devices/command", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if receivedPayload == nil {
		t.Fatal("expected payload")
	}
	if int(receivedPayload["level"].(float64)) != 128 {
		t.Errorf("expected level 128, got %v", receivedPayload["level"])
	}
}

func TestAPICommand_UnknownCommand(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)

	body := `{"node_id": 8, "command": "explode"}`
	req := httptest.NewRequest("POST", "/api/devices/command", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != 400 {
		t.Fatalf("expected 400, got %d", w.Code)
	}
	if !strings.Contains(w.Body.String(), "unknown command") {
		t.Errorf("expected 'unknown command' in body, got: %s", w.Body.String())
	}
}

func TestAPICommand_BadJSON(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)

	req := httptest.NewRequest("POST", "/api/devices/command", strings.NewReader("{invalid"))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != 400 {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestAPICommand_MethodNotAllowed(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)

	req := httptest.NewRequest("GET", "/api/devices/command", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != 405 {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}

func TestAPICommand_MissingLevel(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)

	body := `{"node_id": 8, "command": "set_level"}`
	req := httptest.NewRequest("POST", "/api/devices/command", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != 400 {
		t.Fatalf("expected 400, got %d", w.Code)
	}
	if !strings.Contains(w.Body.String(), "level required") {
		t.Errorf("expected 'level required', got: %s", w.Body.String())
	}
}

// --- POST /api/commission ---

func TestAPICommission_Accepted(t *testing.T) {
	// Commission returns 202 immediately (async).
	// We just need a WS server that won't crash.
	h, srv := testHubWithMatter(t, func(conn *websocket.Conn, msg map[string]interface{}) {
		// Don't respond — commissioning runs in background goroutine
	})
	defer srv.Close()
	defer h.matter.Close()

	mux := testMux(h)

	body := `{"code": "05641540754", "network_only": false}`
	req := httptest.NewRequest("POST", "/api/commission", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != 202 {
		t.Fatalf("expected 202, got %d: %s", w.Code, w.Body.String())
	}

	var resp map[string]string
	json.NewDecoder(w.Body).Decode(&resp)
	if resp["status"] != "commissioning" {
		t.Errorf("expected status 'commissioning', got %q", resp["status"])
	}
}

func TestAPICommission_MissingCode(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)

	body := `{"code": ""}`
	req := httptest.NewRequest("POST", "/api/commission", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != 400 {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestAPICommission_MethodNotAllowed(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)

	req := httptest.NewRequest("GET", "/api/commission", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != 405 {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}

// --- GET /api/events (SSE) ---

func TestAPISSE_Snapshot(t *testing.T) {
	h := testHub(t)
	// start event broadcaster
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go h.eventBroadcaster(ctx)

	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	// Connect to SSE endpoint with short timeout
	client := &http.Client{Timeout: 500 * time.Millisecond}
	resp, err := client.Get(srv.URL + "/api/events")
	if err != nil {
		t.Fatalf("SSE connect: %v", err)
	}
	defer resp.Body.Close()

	if resp.Header.Get("Content-Type") != "text/event-stream" {
		t.Errorf("expected text/event-stream, got %q", resp.Header.Get("Content-Type"))
	}

	// Read first line — should be snapshot
	scanner := bufio.NewScanner(resp.Body)
	if scanner.Scan() {
		line := scanner.Text()
		if !strings.HasPrefix(line, "data: ") {
			t.Fatalf("expected 'data: ...' got %q", line)
		}
		data := line[6:]
		var snapshot map[string]interface{}
		if err := json.Unmarshal([]byte(data), &snapshot); err != nil {
			t.Fatalf("parse snapshot: %v", err)
		}
		if snapshot["type"] != "snapshot" {
			t.Errorf("expected type=snapshot, got %v", snapshot["type"])
		}
		devices, ok := snapshot["devices"].([]interface{})
		if !ok {
			t.Fatal("expected devices array in snapshot")
		}
		if len(devices) != 2 {
			t.Errorf("expected 2 devices in snapshot, got %d", len(devices))
		}
	}
}

func TestAPISSE_EventDelivery(t *testing.T) {
	h := testHub(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go h.eventBroadcaster(ctx)

	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get(srv.URL + "/api/events")
	if err != nil {
		t.Fatalf("SSE connect: %v", err)
	}
	defer resp.Body.Close()

	// Inject an event after snapshot
	go func() {
		time.Sleep(100 * time.Millisecond)
		h.eventCh <- Event{Type: "device_state", DeviceID: 8, Key: "1/6/0", Value: true}
	}()

	scanner := bufio.NewScanner(resp.Body)
	lines := 0
	foundEvent := false
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue // SSE empty line separator
		}
		lines++
		if strings.Contains(line, "device_state") {
			foundEvent = true
			break
		}
		if lines > 5 {
			break
		}
	}

	if !foundEvent {
		t.Error("expected device_state event in SSE stream")
	}
}

// --- POST /api/wifi-credentials ---

func TestAPIWifiCredentials_Success(t *testing.T) {
	h, srv := testHubWithMatter(t, func(conn *websocket.Conn, msg map[string]interface{}) {
		if msg["command"] == "set_wifi_credentials" {
			conn.WriteJSON(map[string]interface{}{
				"message_id": msg["message_id"],
				"error_code": 0,
			})
		}
	})
	defer srv.Close()
	defer h.matter.Close()

	mux := testMux(h)

	body := `{"ssid": "TestWifi", "password": "secret123"}`
	req := httptest.NewRequest("POST", "/api/wifi-credentials", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != 204 {
		t.Fatalf("expected 204, got %d: %s", w.Code, w.Body.String())
	}
}

func TestAPIWifiCredentials_MissingSSID(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)

	body := `{"ssid": "", "password": "secret"}`
	req := httptest.NewRequest("POST", "/api/wifi-credentials", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != 400 {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

// --- GET /api/home (A2UI surface) ---

func TestAPIHomeSurface(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)

	req := httptest.NewRequest("GET", "/api/home", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != 200 {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var surface map[string]interface{}
	if err := json.NewDecoder(w.Body).Decode(&surface); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if surface["surfaceId"] != "home" {
		t.Errorf("expected surfaceId 'home', got %v", surface["surfaceId"])
	}
	if _, ok := surface["components"]; !ok {
		t.Error("expected 'components' in surface")
	}
	if _, ok := surface["theme"]; !ok {
		t.Error("expected 'theme' in surface")
	}
}

// --- addNode ---

func TestAddNode_WithAlias(t *testing.T) {
	h := &Hub{
		cfg:     &config.Config{},
		devices: make(map[int]*DeviceState),
		aliases: map[int]DeviceAlias{
			1: {Name: "현관문 센서", Room: "현관"},
		},
	}

	node := matter.Node{
		NodeID:    1,
		Available: true,
		Attributes: map[string]interface{}{
			"0/40/3": "Generic Sensor",
			"1/29/0": []interface{}{map[string]interface{}{"0": float64(21)}},
			"1/69/0": true,
		},
	}
	ds := h.addNode(node)

	if ds.Name != "현관문 센서" {
		t.Errorf("alias should override name, got %q", ds.Name)
	}
	if ds.Room != "현관" {
		t.Errorf("expected room '현관', got %q", ds.Room)
	}
	if ds.Type != "contact_sensor" {
		t.Errorf("expected type 'contact_sensor', got %q", ds.Type)
	}
	if ds.State["contact"] != true {
		t.Errorf("expected contact=true, got %v", ds.State["contact"])
	}
}

// --- DELETE /api/devices/:node_id ---

func TestAPIDeleteDevice_Success(t *testing.T) {
	h, srv := testHubWithMatter(t, func(conn *websocket.Conn, msg map[string]interface{}) {
		if msg["command"] == "remove_node" {
			conn.WriteJSON(map[string]interface{}{
				"message_id": msg["message_id"],
				"error_code": 0,
			})
		}
	})
	defer srv.Close()
	defer h.matter.Close()

	mux := testMux(h)

	// Verify device exists
	if _, ok := h.devices[8]; !ok {
		t.Fatal("device 8 should exist before delete")
	}

	req := httptest.NewRequest("DELETE", "/api/devices/8", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp map[string]string
	json.NewDecoder(w.Body).Decode(&resp)
	if resp["status"] != "ok" {
		t.Errorf("expected status ok, got %q", resp["status"])
	}

	// Verify device removed from local state
	if _, ok := h.devices[8]; ok {
		t.Error("device 8 should be removed after delete")
	}

	// Verify device_removed event emitted
	select {
	case evt := <-h.eventCh:
		if evt.Type != "device_removed" {
			t.Errorf("expected device_removed event, got %q", evt.Type)
		}
		if evt.DeviceID != 8 {
			t.Errorf("expected device_id 8, got %d", evt.DeviceID)
		}
	case <-time.After(time.Second):
		t.Error("expected device_removed event, got none")
	}
}

func TestAPIDeleteDevice_NotFound(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)

	req := httptest.NewRequest("DELETE", "/api/devices/999", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != 404 {
		t.Fatalf("expected 404, got %d: %s", w.Code, w.Body.String())
	}
}

func TestAPIDeleteDevice_MatterError(t *testing.T) {
	h, srv := testHubWithMatter(t, func(conn *websocket.Conn, msg map[string]interface{}) {
		if msg["command"] == "remove_node" {
			conn.WriteJSON(map[string]interface{}{
				"message_id": msg["message_id"],
				"error_code": 3,
				"details":    "node not found in fabric",
			})
		}
	})
	defer srv.Close()
	defer h.matter.Close()

	mux := testMux(h)

	req := httptest.NewRequest("DELETE", "/api/devices/8", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != 500 {
		t.Fatalf("expected 500, got %d: %s", w.Code, w.Body.String())
	}

	// Device should NOT be removed on error
	if _, ok := h.devices[8]; !ok {
		t.Error("device 8 should still exist after failed delete")
	}
}

func TestAPIDeleteDevice_MethodNotAllowed(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)

	req := httptest.NewRequest("PUT", "/api/devices/8", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != 405 {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}

// --- node_removed event handling ---

func TestHandleMatterEvent_NodeRemoved(t *testing.T) {
	h := testHub(t)

	// Verify device exists
	if _, ok := h.devices[1]; !ok {
		t.Fatal("device 1 should exist")
	}

	// Simulate node_removed event from matterjs
	evt := matter.Event{
		Type: matter.EventNodeRemoved,
		Data: json.RawMessage(`1`),
	}
	h.handleMatterEvent(evt)

	// Verify device removed
	if _, ok := h.devices[1]; ok {
		t.Error("device 1 should be removed after node_removed event")
	}

	// Verify event emitted
	select {
	case e := <-h.eventCh:
		if e.Type != "device_removed" || e.DeviceID != 1 {
			t.Errorf("unexpected event: %+v", e)
		}
	case <-time.After(time.Second):
		t.Error("expected device_removed event")
	}
}

func TestAPICommissionOnNetwork_MissingPinCode(t *testing.T) {
	h := testHub(t)
	mux := http.NewServeMux()
	h.RegisterHTTP(mux)
	ts := httptest.NewServer(mux)
	defer ts.Close()

	// Missing pin_code
	resp, err := http.Post(ts.URL+"/api/commission-on-network", "application/json",
		strings.NewReader(`{"ip_addr":"fd3f::1"}`))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", resp.StatusCode)
	}
}

func TestAPICommissionOnNetwork_MethodNotAllowed(t *testing.T) {
	h := testHub(t)
	mux := http.NewServeMux()
	h.RegisterHTTP(mux)
	ts := httptest.NewServer(mux)
	defer ts.Close()

	resp, err := http.Get(ts.URL + "/api/commission-on-network")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusMethodNotAllowed {
		t.Errorf("expected 405, got %d", resp.StatusCode)
	}
}

func TestAPICommissionOnNetwork_Accepted(t *testing.T) {
	// Test with mock matter client (WebSocket mock)
	matterSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upgrader := websocket.Upgrader{}
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close()

		for {
			_, msg, err := conn.ReadMessage()
			if err != nil {
				return
			}
			var req map[string]interface{}
			if err := json.Unmarshal(msg, &req); err != nil {
				continue
			}

			cmd, _ := req["command"].(string)
			id, _ := req["message_id"].(string)

			switch cmd {
			case "server_info":
				resp := fmt.Sprintf(`{"message_id":"%s","result":{"sdk_version":"1.0","fabric_id":1,"bluetooth_enabled":true,"thread_credentials_set":false}}`, id)
				conn.WriteMessage(websocket.TextMessage, []byte(resp))
			case "start_listening":
				resp := fmt.Sprintf(`{"message_id":"%s","result":{}}`, id)
				conn.WriteMessage(websocket.TextMessage, []byte(resp))
			case "commission_on_network":
				args := req["args"].(map[string]interface{})
				pinCode := args["setup_pin_code"].(float64)
				if pinCode == 56204424 {
					resp := fmt.Sprintf(`{"message_id":"%s","result":{"node_id":10,"date_commissioned":"2026-01-01","available":true,"attributes":{"1/29/0":[{"0":21}]}}}`, id)
					conn.WriteMessage(websocket.TextMessage, []byte(resp))
				}
			case "get_nodes":
				resp := fmt.Sprintf(`{"message_id":"%s","result":[]}`, id)
				conn.WriteMessage(websocket.TextMessage, []byte(resp))
			}
		}
	}))
	defer matterSrv.Close()

	wsURL := "ws" + strings.TrimPrefix(matterSrv.URL, "http")

	cfg := &config.Config{
		MatterWSURL: wsURL,
	}
	h := New(cfg)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go h.Run(ctx)
	time.Sleep(500 * time.Millisecond) // Wait for matter connection

	mux := http.NewServeMux()
	h.RegisterHTTP(mux)
	ts := httptest.NewServer(mux)
	defer ts.Close()

	resp, err := http.Post(ts.URL+"/api/commission-on-network", "application/json",
		strings.NewReader(`{"pin_code":56204424,"ip_addr":"fd3f:a8c0:1556:1:5ea6:9e21:f21e:cb08"}`))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusAccepted {
		t.Errorf("expected 202, got %d", resp.StatusCode)
	}

	var result map[string]string
	json.NewDecoder(resp.Body).Decode(&result)
	if result["status"] != "commissioning_on_network" {
		t.Errorf("expected status 'commissioning_on_network', got %q", result["status"])
	}

	// Wait for background commissioning to complete
	time.Sleep(time.Second)
	cancel()
}

func TestAddNode_DeviceTypes(t *testing.T) {
	tests := []struct {
		typeID   float64
		expected string
	}{
		{21, "contact_sensor"},
		{256, "on_off_light"},
		{257, "dimmable_light"},
		{266, "on_off_plug"},
		{268, "color_temp_light"},
		{269, "extended_color_light"},
		{770, "temperature_sensor"},
		{775, "humidity_sensor"},
		{999, fmt.Sprintf("device_%d", 999)},
	}

	for _, tc := range tests {
		h := &Hub{
			cfg:     &config.Config{},
			devices: make(map[int]*DeviceState),
			aliases: make(map[int]DeviceAlias),
		}
		node := matter.Node{
			NodeID:    1,
			Available: true,
			Attributes: map[string]interface{}{
				"1/29/0": []interface{}{map[string]interface{}{"0": tc.typeID}},
			},
		}
		ds := h.addNode(node)
		if ds.Type != tc.expected {
			t.Errorf("typeID %.0f: expected %q, got %q", tc.typeID, tc.expected, ds.Type)
		}
	}
}

func TestAddNode_DimmableLight_State(t *testing.T) {
	h := &Hub{cfg: &config.Config{}, devices: make(map[int]*DeviceState), aliases: make(map[int]DeviceAlias)}
	ds := h.addNode(matter.Node{
		NodeID: 5, Available: true,
		Attributes: map[string]interface{}{
			"1/29/0": []interface{}{map[string]interface{}{"0": float64(257)}},
			"1/6/0": true, "1/8/0": float64(200),
		},
	})
	if ds.Type != "dimmable_light" { t.Errorf("got type %q", ds.Type) }
	if ds.State["on"] != true { t.Errorf("got on=%v", ds.State["on"]) }
	if ds.State["level"] != float64(200) { t.Errorf("got level=%v", ds.State["level"]) }
}

func TestAddNode_ColorTempLight_State(t *testing.T) {
	h := &Hub{cfg: &config.Config{}, devices: make(map[int]*DeviceState), aliases: make(map[int]DeviceAlias)}
	ds := h.addNode(matter.Node{
		NodeID: 6, Available: true,
		Attributes: map[string]interface{}{
			"1/29/0": []interface{}{map[string]interface{}{"0": float64(268)}},
			"1/6/0": true, "1/8/0": float64(180), "1/768/7": float64(300),
		},
	})
	if ds.Type != "color_temp_light" { t.Errorf("got type %q", ds.Type) }
	if ds.State["level"] != float64(180) { t.Errorf("got level=%v", ds.State["level"]) }
	if ds.State["color_temp"] != float64(300) { t.Errorf("got color_temp=%v", ds.State["color_temp"]) }
}

func TestAddNode_ExtendedColorLight_State(t *testing.T) {
	h := &Hub{cfg: &config.Config{}, devices: make(map[int]*DeviceState), aliases: make(map[int]DeviceAlias)}
	ds := h.addNode(matter.Node{
		NodeID: 7, Available: true,
		Attributes: map[string]interface{}{
			"1/29/0": []interface{}{map[string]interface{}{"0": float64(269)}},
			"1/6/0": true, "1/8/0": float64(254),
			"1/768/0": float64(120), "1/768/1": float64(200), "1/768/7": float64(250),
		},
	})
	if ds.Type != "extended_color_light" { t.Errorf("got type %q", ds.Type) }
	if ds.State["hue"] != float64(120) { t.Errorf("got hue=%v", ds.State["hue"]) }
	if ds.State["saturation"] != float64(200) { t.Errorf("got saturation=%v", ds.State["saturation"]) }
}

func TestAddNode_TemperatureSensor_State(t *testing.T) {
	h := &Hub{cfg: &config.Config{}, devices: make(map[int]*DeviceState), aliases: make(map[int]DeviceAlias)}
	ds := h.addNode(matter.Node{
		NodeID: 10, Available: true,
		Attributes: map[string]interface{}{
			"1/29/0": []interface{}{map[string]interface{}{"0": float64(770)}},
			"1/1026/0": float64(2350),
		},
	})
	if ds.Type != "temperature_sensor" { t.Errorf("got type %q", ds.Type) }
	if ds.State["temperature"] != float64(2350) { t.Errorf("got temperature=%v", ds.State["temperature"]) }
}

func TestAddNode_HumiditySensor_State(t *testing.T) {
	h := &Hub{cfg: &config.Config{}, devices: make(map[int]*DeviceState), aliases: make(map[int]DeviceAlias)}
	ds := h.addNode(matter.Node{
		NodeID: 11, Available: true,
		Attributes: map[string]interface{}{
			"1/29/0": []interface{}{map[string]interface{}{"0": float64(775)}},
			"1/1029/0": float64(4500),
		},
	})
	if ds.Type != "humidity_sensor" { t.Errorf("got type %q", ds.Type) }
	if ds.State["humidity"] != float64(4500) { t.Errorf("got humidity=%v", ds.State["humidity"]) }
}

func TestAttrMap_SSEMapping(t *testing.T) {
	expected := map[string]string{
		"1/6/0": "on", "1/69/0": "contact", "1/8/0": "level",
		"1/768/0": "hue", "1/768/1": "saturation", "1/768/7": "color_temp",
		"1/1026/0": "temperature", "1/1029/0": "humidity",
	}
	for path, key := range expected {
		if attrMap[path] != key {
			t.Errorf("attrMap[%q] = %q, want %q", path, attrMap[path], key)
		}
	}
	if len(attrMap) != len(expected) {
		t.Errorf("attrMap has %d entries, want %d", len(attrMap), len(expected))
	}
}

// --- Edge case tests ---

func TestAddNode_Temperature_Negative(t *testing.T) {
	h := &Hub{cfg: &config.Config{}, devices: make(map[int]*DeviceState), aliases: make(map[int]DeviceAlias)}
	ds := h.addNode(matter.Node{
		NodeID: 20, Available: true,
		Attributes: map[string]interface{}{
			"1/29/0":   []interface{}{map[string]interface{}{"0": float64(770)}},
			"1/1026/0": float64(-1000), // -10.00°C
		},
	})
	if ds.State["temperature"] != float64(-1000) {
		t.Errorf("negative temperature: expected -1000, got %v", ds.State["temperature"])
	}
}

func TestAddNode_Temperature_Zero(t *testing.T) {
	h := &Hub{cfg: &config.Config{}, devices: make(map[int]*DeviceState), aliases: make(map[int]DeviceAlias)}
	ds := h.addNode(matter.Node{
		NodeID: 21, Available: true,
		Attributes: map[string]interface{}{
			"1/29/0":   []interface{}{map[string]interface{}{"0": float64(770)}},
			"1/1026/0": float64(0), // 0.00°C
		},
	})
	if ds.State["temperature"] != float64(0) {
		t.Errorf("zero temperature: expected 0, got %v", ds.State["temperature"])
	}
}

func TestAddNode_Humidity_Full(t *testing.T) {
	h := &Hub{cfg: &config.Config{}, devices: make(map[int]*DeviceState), aliases: make(map[int]DeviceAlias)}
	ds := h.addNode(matter.Node{
		NodeID: 22, Available: true,
		Attributes: map[string]interface{}{
			"1/29/0":   []interface{}{map[string]interface{}{"0": float64(775)}},
			"1/1029/0": float64(10000), // 100.00%
		},
	})
	if ds.State["humidity"] != float64(10000) {
		t.Errorf("100%% humidity: expected 10000, got %v", ds.State["humidity"])
	}
}

func TestAddNode_Humidity_Zero(t *testing.T) {
	h := &Hub{cfg: &config.Config{}, devices: make(map[int]*DeviceState), aliases: make(map[int]DeviceAlias)}
	ds := h.addNode(matter.Node{
		NodeID: 23, Available: true,
		Attributes: map[string]interface{}{
			"1/29/0":   []interface{}{map[string]interface{}{"0": float64(775)}},
			"1/1029/0": float64(0),
		},
	})
	if ds.State["humidity"] != float64(0) {
		t.Errorf("0%% humidity: expected 0, got %v", ds.State["humidity"])
	}
}

func TestAddNode_Level_Boundaries(t *testing.T) {
	h := &Hub{cfg: &config.Config{}, devices: make(map[int]*DeviceState), aliases: make(map[int]DeviceAlias)}
	// level=0 (minimum)
	ds := h.addNode(matter.Node{
		NodeID: 30, Available: true,
		Attributes: map[string]interface{}{
			"1/29/0": []interface{}{map[string]interface{}{"0": float64(257)}},
			"1/6/0": false, "1/8/0": float64(0),
		},
	})
	if ds.State["level"] != float64(0) {
		t.Errorf("level min: expected 0, got %v", ds.State["level"])
	}
	// level=254 (maximum)
	h2 := &Hub{cfg: &config.Config{}, devices: make(map[int]*DeviceState), aliases: make(map[int]DeviceAlias)}
	ds2 := h2.addNode(matter.Node{
		NodeID: 31, Available: true,
		Attributes: map[string]interface{}{
			"1/29/0": []interface{}{map[string]interface{}{"0": float64(257)}},
			"1/6/0": true, "1/8/0": float64(254),
		},
	})
	if ds2.State["level"] != float64(254) {
		t.Errorf("level max: expected 254, got %v", ds2.State["level"])
	}
}

func TestAttrMap_UnknownPath_Ignored(t *testing.T) {
	h := &Hub{cfg: &config.Config{}, devices: make(map[int]*DeviceState), aliases: make(map[int]DeviceAlias)}
	ds := h.addNode(matter.Node{
		NodeID: 40, Available: true,
		Attributes: map[string]interface{}{
			"1/29/0":   []interface{}{map[string]interface{}{"0": float64(256)}},
			"1/6/0":    true,
			"1/999/0":  "unknown_value", // unknown attribute — NOT in attrMap
		},
	})
	// "on" should be parsed via attrMap
	if ds.State["on"] != true {
		t.Errorf("expected on=true, got %v", ds.State["on"])
	}
	// unknown path should NOT appear in state (attrMap doesn't have it)
	if _, exists := ds.State["1/999/0"]; exists {
		t.Errorf("unknown attribute path should not be in initial state via attrMap")
	}
}

// --- SSE regression: attrMap handles on/off and contact correctly ---

func TestHandleMatterEvent_OnOff_Regression(t *testing.T) {
	h := testHub(t)
	// Seed a device
	h.mu.Lock()
	h.devices[8] = &DeviceState{NodeID: 8, Type: "on_off_plug", State: map[string]interface{}{"on": false}}
	h.mu.Unlock()

	// Simulate attribute update for on/off
	evt := matter.Event{
		Type: matter.EventAttributeUpdated,
		Data: mustMarshal(t, []interface{}{8, "1/6/0", true}),
	}
	h.handleMatterEvent(evt)

	h.mu.RLock()
	ds := h.devices[8]
	h.mu.RUnlock()

	if ds.State["on"] != true {
		t.Errorf("SSE regression: on/off should be true after attribute update, got %v", ds.State["on"])
	}
}

func TestHandleMatterEvent_Contact_Regression(t *testing.T) {
	h := testHub(t)
	h.mu.Lock()
	h.devices[1] = &DeviceState{NodeID: 1, Type: "contact_sensor", State: map[string]interface{}{"contact": false}}
	h.mu.Unlock()

	evt := matter.Event{
		Type: matter.EventAttributeUpdated,
		Data: mustMarshal(t, []interface{}{1, "1/69/0", true}),
	}
	h.handleMatterEvent(evt)

	h.mu.RLock()
	ds := h.devices[1]
	h.mu.RUnlock()

	if ds.State["contact"] != true {
		t.Errorf("SSE regression: contact should be true after attribute update, got %v", ds.State["contact"])
	}
}

func TestHandleMatterEvent_Level_Update(t *testing.T) {
	h := testHub(t)
	h.mu.Lock()
	h.devices[5] = &DeviceState{NodeID: 5, Type: "dimmable_light", State: map[string]interface{}{"on": true, "level": float64(100)}}
	h.mu.Unlock()

	evt := matter.Event{
		Type: matter.EventAttributeUpdated,
		Data: mustMarshal(t, []interface{}{5, "1/8/0", float64(200)}),
	}
	h.handleMatterEvent(evt)

	h.mu.RLock()
	ds := h.devices[5]
	h.mu.RUnlock()

	if ds.State["level"] != float64(200) {
		t.Errorf("level should be 200 after update, got %v", ds.State["level"])
	}
}

func TestHandleMatterEvent_Temperature_Update(t *testing.T) {
	h := testHub(t)
	h.mu.Lock()
	h.devices[10] = &DeviceState{NodeID: 10, Type: "temperature_sensor", State: map[string]interface{}{"temperature": float64(2000)}}
	h.mu.Unlock()

	evt := matter.Event{
		Type: matter.EventAttributeUpdated,
		Data: mustMarshal(t, []interface{}{10, "1/1026/0", float64(2500)}),
	}
	h.handleMatterEvent(evt)

	h.mu.RLock()
	ds := h.devices[10]
	h.mu.RUnlock()

	if ds.State["temperature"] != float64(2500) {
		t.Errorf("temperature should be 2500 after update, got %v", ds.State["temperature"])
	}
}

func TestHandleMatterEvent_UnknownPath_Stored_Raw(t *testing.T) {
	h := testHub(t)
	h.mu.Lock()
	h.devices[40] = &DeviceState{NodeID: 40, Type: "on_off_light", State: map[string]interface{}{}}
	h.mu.Unlock()

	// Unknown path should be stored by raw path (not in attrMap)
	evt := matter.Event{
		Type: matter.EventAttributeUpdated,
		Data: mustMarshal(t, []interface{}{40, "1/999/0", "raw_value"}),
	}
	h.handleMatterEvent(evt)

	h.mu.RLock()
	ds := h.devices[40]
	h.mu.RUnlock()

	if ds.State["1/999/0"] != "raw_value" {
		t.Errorf("unknown path should be stored raw, got %v", ds.State["1/999/0"])
	}
}

func mustMarshal(t *testing.T, v interface{}) json.RawMessage {
	t.Helper()
	data, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

// --- SSE key conversion tests (raw path → attrMap name) ---

func TestSSEKey_OnOff_Converted(t *testing.T) {
	h := testHub(t)
	h.mu.Lock()
	h.devices[8] = &DeviceState{NodeID: 8, Type: "on_off_plug", State: map[string]interface{}{"on": false}}
	h.mu.Unlock()

	evt := matter.Event{
		Type: matter.EventAttributeUpdated,
		Data: mustMarshal(t, []interface{}{8, "1/6/0", true}),
	}
	h.handleMatterEvent(evt)

	// Read from eventCh — key should be "on", not "1/6/0"
	select {
	case e := <-h.eventCh:
		if e.Key != "on" {
			t.Errorf("SSE key should be 'on', got %q", e.Key)
		}
		if e.Value != true {
			t.Errorf("SSE value should be true, got %v", e.Value)
		}
	default:
		t.Fatal("no event in eventCh")
	}
}

func TestSSEKey_Contact_Converted(t *testing.T) {
	h := testHub(t)
	h.mu.Lock()
	h.devices[1] = &DeviceState{NodeID: 1, Type: "contact_sensor", State: map[string]interface{}{"contact": false}}
	h.mu.Unlock()

	evt := matter.Event{
		Type: matter.EventAttributeUpdated,
		Data: mustMarshal(t, []interface{}{1, "1/69/0", true}),
	}
	h.handleMatterEvent(evt)

	select {
	case e := <-h.eventCh:
		if e.Key != "contact" {
			t.Errorf("SSE key should be 'contact', got %q", e.Key)
		}
	default:
		t.Fatal("no event in eventCh")
	}
}

func TestSSEKey_Level_Converted(t *testing.T) {
	h := testHub(t)
	h.mu.Lock()
	h.devices[5] = &DeviceState{NodeID: 5, Type: "dimmable_light", State: map[string]interface{}{}}
	h.mu.Unlock()

	evt := matter.Event{
		Type: matter.EventAttributeUpdated,
		Data: mustMarshal(t, []interface{}{5, "1/8/0", float64(200)}),
	}
	h.handleMatterEvent(evt)

	select {
	case e := <-h.eventCh:
		if e.Key != "level" {
			t.Errorf("SSE key should be 'level', got %q", e.Key)
		}
	default:
		t.Fatal("no event in eventCh")
	}
}

func TestSSEKey_Temperature_Converted(t *testing.T) {
	h := testHub(t)
	h.mu.Lock()
	h.devices[10] = &DeviceState{NodeID: 10, Type: "temperature_sensor", State: map[string]interface{}{}}
	h.mu.Unlock()

	evt := matter.Event{
		Type: matter.EventAttributeUpdated,
		Data: mustMarshal(t, []interface{}{10, "1/1026/0", float64(2350)}),
	}
	h.handleMatterEvent(evt)

	select {
	case e := <-h.eventCh:
		if e.Key != "temperature" {
			t.Errorf("SSE key should be 'temperature', got %q", e.Key)
		}
	default:
		t.Fatal("no event in eventCh")
	}
}

func TestSSEKey_UnknownPath_RawPreserved(t *testing.T) {
	h := testHub(t)
	h.mu.Lock()
	h.devices[40] = &DeviceState{NodeID: 40, Type: "on_off_light", State: map[string]interface{}{}}
	h.mu.Unlock()

	evt := matter.Event{
		Type: matter.EventAttributeUpdated,
		Data: mustMarshal(t, []interface{}{40, "2/999/0", "raw"}),
	}
	h.handleMatterEvent(evt)

	select {
	case e := <-h.eventCh:
		if e.Key != "2/999/0" {
			t.Errorf("unknown path should be preserved raw, got %q", e.Key)
		}
	default:
		t.Fatal("no event in eventCh")
	}
}

// --- EventNodeUpdated / EventNodeAdded tests ---

func TestHandleMatterEvent_NodeUpdated_AvailableTrue(t *testing.T) {
	h := testHub(t)
	// Set device 1 to unavailable
	h.mu.Lock()
	h.devices[1].Available = false
	h.mu.Unlock()

	// Simulate node_updated event with available=true
	nodeData := mustMarshal(t, matter.Node{NodeID: 1, Available: true})
	evt := matter.Event{Type: matter.EventNodeUpdated, Data: nodeData}
	h.handleMatterEvent(evt)

	// Verify available is now true
	h.mu.RLock()
	ds := h.devices[1]
	h.mu.RUnlock()
	if !ds.Available {
		t.Error("node 1 should be available after node_updated")
	}

	// Verify SSE event emitted
	select {
	case e := <-h.eventCh:
		if e.Type != "device_state" || e.Key != "available" || e.Value != true {
			t.Errorf("expected device_state available=true, got %+v", e)
		}
	default:
		t.Fatal("expected available change event in eventCh")
	}
}

func TestHandleMatterEvent_NodeUpdated_AvailableFalse(t *testing.T) {
	h := testHub(t)
	// Device 1 starts available (testHub default)
	h.mu.RLock()
	if !h.devices[1].Available {
		t.Fatal("device 1 should start available")
	}
	h.mu.RUnlock()

	// Simulate node going offline
	nodeData := mustMarshal(t, matter.Node{NodeID: 1, Available: false})
	evt := matter.Event{Type: matter.EventNodeUpdated, Data: nodeData}
	h.handleMatterEvent(evt)

	h.mu.RLock()
	ds := h.devices[1]
	h.mu.RUnlock()
	if ds.Available {
		t.Error("node 1 should be unavailable after node_updated")
	}

	select {
	case e := <-h.eventCh:
		if e.Type != "device_state" || e.Key != "available" || e.Value != false {
			t.Errorf("expected device_state available=false, got %+v", e)
		}
	default:
		t.Fatal("expected available change event")
	}
}

func TestHandleMatterEvent_NodeUpdated_NoChange(t *testing.T) {
	h := testHub(t)
	// Device 1 already available — no event should be emitted
	nodeData := mustMarshal(t, matter.Node{NodeID: 1, Available: true})
	evt := matter.Event{Type: matter.EventNodeUpdated, Data: nodeData}
	h.handleMatterEvent(evt)

	// No event should be in channel (no change)
	select {
	case e := <-h.eventCh:
		t.Errorf("no event expected when available unchanged, got %+v", e)
	default:
		// OK — no event
	}
}

func TestHandleMatterEvent_NodeAdded_NewDevice(t *testing.T) {
	h := testHub(t)
	// Verify node 99 doesn't exist
	h.mu.RLock()
	_, exists := h.devices[99]
	h.mu.RUnlock()
	if exists {
		t.Fatal("node 99 should not exist initially")
	}

	// Simulate node_added for a new device
	node := matter.Node{
		NodeID:    99,
		Available: true,
		Attributes: map[string]interface{}{
			"1/29/0": []interface{}{map[string]interface{}{"0": float64(266)}},
			"1/6/0":  true,
		},
	}
	nodeData := mustMarshal(t, node)
	evt := matter.Event{Type: matter.EventNodeAdded, Data: nodeData}
	h.handleMatterEvent(evt)

	// Verify device was registered
	h.mu.RLock()
	ds, ok := h.devices[99]
	h.mu.RUnlock()
	if !ok {
		t.Fatal("node 99 should be registered after node_added")
	}
	if ds.Type != "on_off_plug" {
		t.Errorf("expected type on_off_plug, got %q", ds.Type)
	}
	if ds.State["on"] != true {
		t.Errorf("expected on=true, got %v", ds.State["on"])
	}

	// Verify device_added event emitted
	select {
	case e := <-h.eventCh:
		if e.Type != "device_added" || e.DeviceID != 99 {
			t.Errorf("expected device_added node 99, got %+v", e)
		}
	default:
		t.Fatal("expected device_added event")
	}
}

func TestHandleMatterEvent_NodeUpdated_UnknownNode(t *testing.T) {
	h := testHub(t)
	// node_updated for unknown node — should not crash, just log
	nodeData := mustMarshal(t, matter.Node{NodeID: 999, Available: true})
	evt := matter.Event{Type: matter.EventNodeUpdated, Data: nodeData}
	h.handleMatterEvent(evt) // should not panic

	// Unknown node should NOT be added by node_updated (only node_added does that)
	h.mu.RLock()
	_, exists := h.devices[999]
	h.mu.RUnlock()
	if exists {
		t.Error("node_updated should not register unknown nodes")
	}
}

// --- PATCH /api/devices/:id ---

func TestAPIPatchDevice_NameRoom(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	// PATCH name + room
	body := strings.NewReader(`{"name":"부엌 플러그","room":"부엌"}`)
	req, _ := http.NewRequest(http.MethodPatch, srv.URL+"/api/devices/8", body)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}

	var dev DeviceState
	json.NewDecoder(resp.Body).Decode(&dev)
	if dev.Name != "부엌 플러그" {
		t.Errorf("expected name '부엌 플러그', got %q", dev.Name)
	}
	if dev.Room != "부엌" {
		t.Errorf("expected room '부엌', got %q", dev.Room)
	}

	// Verify in-memory state
	h.mu.RLock()
	d := h.devices[8]
	h.mu.RUnlock()
	if d.Name != "부엌 플러그" || d.Room != "부엌" {
		t.Error("device state not updated in memory")
	}
}

func TestAPIPatchDevice_PartialUpdate(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	// PATCH only name (room should stay)
	body := strings.NewReader(`{"name":"새 이름"}`)
	req, _ := http.NewRequest(http.MethodPatch, srv.URL+"/api/devices/1", body)
	req.Header.Set("Content-Type", "application/json")
	resp, _ := http.DefaultClient.Do(req)
	defer resp.Body.Close()

	var dev DeviceState
	json.NewDecoder(resp.Body).Decode(&dev)
	if dev.Name != "새 이름" {
		t.Errorf("name should be '새 이름', got %q", dev.Name)
	}
	// Room should keep original value from testHub
	if dev.Room != "현관" {
		t.Errorf("room should stay '현관', got %q", dev.Room)
	}
}

func TestAPIPatchDevice_NotFound(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	body := strings.NewReader(`{"name":"x"}`)
	req, _ := http.NewRequest(http.MethodPatch, srv.URL+"/api/devices/999", body)
	req.Header.Set("Content-Type", "application/json")
	resp, _ := http.DefaultClient.Do(req)
	defer resp.Body.Close()

	if resp.StatusCode != 404 {
		t.Errorf("expected 404, got %d", resp.StatusCode)
	}
}

func TestAPIPatchDevice_BadJSON(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	body := strings.NewReader(`not json`)
	req, _ := http.NewRequest(http.MethodPatch, srv.URL+"/api/devices/8", body)
	req.Header.Set("Content-Type", "application/json")
	resp, _ := http.DefaultClient.Do(req)
	defer resp.Body.Close()

	if resp.StatusCode != 400 {
		t.Errorf("expected 400, got %d", resp.StatusCode)
	}
}

// --- GET /api/devices?filter ---

func TestAPIGetDevices_FilterRoom(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	resp, _ := http.Get(srv.URL + "/api/devices?room=" + "현관")
	defer resp.Body.Close()

	var devices []DeviceState
	json.NewDecoder(resp.Body).Decode(&devices)

	for _, d := range devices {
		if d.Room != "현관" {
			t.Errorf("filter failed: expected room '현관', got %q (node %d)", d.Room, d.NodeID)
		}
	}
}

func TestAPIGetDevices_FilterType(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	resp, _ := http.Get(srv.URL + "/api/devices?type=on_off_plug")
	defer resp.Body.Close()

	var devices []DeviceState
	json.NewDecoder(resp.Body).Decode(&devices)

	for _, d := range devices {
		if d.Type != "on_off_plug" {
			t.Errorf("filter failed: expected type 'on_off_plug', got %q (node %d)", d.Type, d.NodeID)
		}
	}
}

func TestAPIGetDevices_FilterNoMatch(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	resp, _ := http.Get(srv.URL + "/api/devices?room=없는방")
	defer resp.Body.Close()

	var devices []DeviceState
	json.NewDecoder(resp.Body).Decode(&devices)

	if len(devices) != 0 {
		t.Errorf("expected 0 devices for nonexistent room, got %d", len(devices))
	}
}

// --- GET /api/system ---

func TestAPISystem(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	resp, err := http.Get(srv.URL + "/api/system")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}

	var info map[string]interface{}
	json.NewDecoder(resp.Body).Decode(&info)

	if info["version"] != "0.9.0" {
		t.Errorf("expected version '0.9.0', got %v", info["version"])
	}
	if info["devices"] == nil {
		t.Error("expected 'devices' field")
	}
	if info["uptime"] == nil {
		t.Error("expected 'uptime' field")
	}
}

// --- GET /dashboard ---

func TestAPIDashboardRedirect(t *testing.T) {
	h := testHub(t)
	h.cfg.MatterWSURL = "ws://localhost:5580"
	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	client := &http.Client{
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			return http.ErrUseLastResponse // don't follow redirects
		},
	}

	resp, err := client.Get(srv.URL + "/dashboard")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusTemporaryRedirect {
		t.Fatalf("expected 307, got %d", resp.StatusCode)
	}

	loc := resp.Header.Get("Location")
	if loc != "http://localhost:5580" {
		t.Errorf("expected redirect to http://localhost:5580, got %q", loc)
	}
}
