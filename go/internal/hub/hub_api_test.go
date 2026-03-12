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

func TestAddNode_DeviceTypes(t *testing.T) {
	tests := []struct {
		typeID   float64
		expected string
	}{
		{21, "contact_sensor"},
		{256, "on_off_light"},
		{266, "on_off_plug"},
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
