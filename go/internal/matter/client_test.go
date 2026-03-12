package matter

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

// mockWSServer creates a test WS server.
// handler receives each incoming message and should respond.
func mockWSServer(t *testing.T, handler func(conn *websocket.Conn, msg map[string]interface{})) (*httptest.Server, string) {
	t.Helper()
	upgrader := websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			t.Logf("upgrade error: %v", err)
			return
		}
		defer conn.Close()

		// Send server info (first message)
		info := ServerInfo{
			FabricID:             1,
			SDKVersion:           "test",
			BluetoothEnabled:     true,
			ThreadCredentialsSet: false,
		}
		if err := conn.WriteJSON(info); err != nil {
			return
		}

		// Read and handle messages
		for {
			var msg map[string]interface{}
			if err := conn.ReadJSON(&msg); err != nil {
				return
			}
			handler(conn, msg)
		}
	}))

	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http")
	return srv, wsURL
}

func TestSetThreadDataset_Success(t *testing.T) {
	srv, wsURL := mockWSServer(t, func(conn *websocket.Conn, msg map[string]interface{}) {
		// Verify command and args
		if msg["command"] != "set_thread_dataset" {
			t.Errorf("expected command set_thread_dataset, got %v", msg["command"])
		}
		args, _ := msg["args"].(map[string]interface{})
		if args["dataset"] != "0e080000" {
			t.Errorf("expected dataset 0e080000, got %v", args["dataset"])
		}

		// Send success response
		resp := map[string]interface{}{
			"message_id": msg["message_id"],
			"result":     nil,
			"error_code": 0,
		}
		conn.WriteJSON(resp)
	})
	defer srv.Close()

	client := NewClient(wsURL)
	ctx := context.Background()
	if err := client.Connect(ctx); err != nil {
		t.Fatal(err)
	}
	defer client.Close()

	// Start read loop
	readErr := make(chan error, 1)
	go func() { readErr <- client.ReadLoop(ctx) }()

	// Give read loop time to start
	time.Sleep(10 * time.Millisecond)

	err := client.SetThreadDataset(ctx, "0e080000")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestSetThreadDataset_ErrorResponse(t *testing.T) {
	srv, wsURL := mockWSServer(t, func(conn *websocket.Conn, msg map[string]interface{}) {
		resp := map[string]interface{}{
			"message_id": msg["message_id"],
			"error_code": 3,
			"details":    "dataset invalid format",
		}
		conn.WriteJSON(resp)
	})
	defer srv.Close()

	client := NewClient(wsURL)
	ctx := context.Background()
	if err := client.Connect(ctx); err != nil {
		t.Fatal(err)
	}
	defer client.Close()

	readErr := make(chan error, 1)
	go func() { readErr <- client.ReadLoop(ctx) }()
	time.Sleep(10 * time.Millisecond)

	err := client.SetThreadDataset(ctx, "invalid")
	if err == nil {
		t.Fatal("expected error for error_code=3")
	}
	if !strings.Contains(err.Error(), "dataset invalid format") {
		t.Errorf("error should mention details, got: %v", err)
	}
}

func TestSetThreadDataset_Timeout(t *testing.T) {
	srv, wsURL := mockWSServer(t, func(conn *websocket.Conn, msg map[string]interface{}) {
		// Never respond — simulate timeout
		time.Sleep(15 * time.Second)
	})
	defer srv.Close()

	client := NewClient(wsURL)
	ctx := context.Background()
	if err := client.Connect(ctx); err != nil {
		t.Fatal(err)
	}
	defer client.Close()

	readErr := make(chan error, 1)
	go func() { readErr <- client.ReadLoop(ctx) }()
	time.Sleep(10 * time.Millisecond)

	// SetThreadDataset has 10s timeout internally
	err := client.SetThreadDataset(ctx, "0e080000")
	if err == nil {
		t.Fatal("expected timeout error")
	}
	if !strings.Contains(err.Error(), "timeout") {
		t.Errorf("expected timeout error, got: %v", err)
	}
}

func TestSendCommand_Success(t *testing.T) {
	srv, wsURL := mockWSServer(t, func(conn *websocket.Conn, msg map[string]interface{}) {
		if msg["command"] != "device_command" {
			t.Errorf("expected device_command, got %v", msg["command"])
		}
		args, _ := msg["args"].(map[string]interface{})
		if int(args["node_id"].(float64)) != 8 {
			t.Errorf("expected node_id 8, got %v", args["node_id"])
		}
		if int(args["cluster_id"].(float64)) != 6 {
			t.Errorf("expected cluster_id 6 (OnOff), got %v", args["cluster_id"])
		}
		if args["command_name"] != "on" {
			t.Errorf("expected command_name 'on', got %v", args["command_name"])
		}

		resp := map[string]interface{}{
			"message_id": msg["message_id"],
			"result":     nil,
			"error_code": 0,
		}
		conn.WriteJSON(resp)
	})
	defer srv.Close()

	client := NewClient(wsURL)
	ctx := context.Background()
	if err := client.Connect(ctx); err != nil {
		t.Fatal(err)
	}
	defer client.Close()

	readErr := make(chan error, 1)
	go func() { readErr <- client.ReadLoop(ctx) }()
	time.Sleep(10 * time.Millisecond)

	err := client.SendCommand(ctx, 8, 1, 6, "on", nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestGetNodes_Success(t *testing.T) {
	srv, wsURL := mockWSServer(t, func(conn *websocket.Conn, msg map[string]interface{}) {
		if msg["command"] != "get_nodes" {
			t.Errorf("expected get_nodes, got %v", msg["command"])
		}

		nodes := []Node{
			{NodeID: 1, Available: true, Attributes: map[string]interface{}{"0/40/3": "Contact Sensor"}},
			{NodeID: 8, Available: true, Attributes: map[string]interface{}{"1/6/0": true}},
		}
		nodesJSON, _ := json.Marshal(nodes)

		resp := map[string]interface{}{
			"message_id": msg["message_id"],
			"result":     json.RawMessage(nodesJSON),
			"error_code": 0,
		}
		conn.WriteJSON(resp)
	})
	defer srv.Close()

	client := NewClient(wsURL)
	ctx := context.Background()
	if err := client.Connect(ctx); err != nil {
		t.Fatal(err)
	}
	defer client.Close()

	readErr := make(chan error, 1)
	go func() { readErr <- client.ReadLoop(ctx) }()
	time.Sleep(10 * time.Millisecond)

	nodes, err := client.GetNodes(ctx)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(nodes) != 2 {
		t.Fatalf("expected 2 nodes, got %d", len(nodes))
	}
	if nodes[0].NodeID != 1 || nodes[1].NodeID != 8 {
		t.Errorf("unexpected node IDs: %d, %d", nodes[0].NodeID, nodes[1].NodeID)
	}
}

func TestConnect_ServerInfo(t *testing.T) {
	srv, wsURL := mockWSServer(t, func(conn *websocket.Conn, msg map[string]interface{}) {
		// No messages expected for this test
	})
	defer srv.Close()

	client := NewClient(wsURL)
	ctx := context.Background()
	if err := client.Connect(ctx); err != nil {
		t.Fatal(err)
	}
	defer client.Close()

	info := client.Info()
	if info == nil {
		t.Fatal("expected server info")
	}
	if info.FabricID != 1 {
		t.Errorf("expected fabric_id 1, got %d", info.FabricID)
	}
	if info.SDKVersion != "test" {
		t.Errorf("expected sdk_version 'test', got %q", info.SDKVersion)
	}
	if info.ThreadCredentialsSet {
		t.Error("expected thread_credentials_set=false")
	}
}

func TestParseAttributeUpdate_Valid(t *testing.T) {
	data := json.RawMessage(`[1, "1/69/0", true]`)
	upd, err := ParseAttributeUpdate(data)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if upd.NodeID != 1 {
		t.Errorf("expected nodeID 1, got %d", upd.NodeID)
	}
	if upd.Path != "1/69/0" {
		t.Errorf("expected path '1/69/0', got %q", upd.Path)
	}
	if upd.Value != true {
		t.Errorf("expected value true, got %v", upd.Value)
	}
}

func TestParseAttributeUpdate_NumericValue(t *testing.T) {
	data := json.RawMessage(`[8, "1/6/0", false]`)
	upd, err := ParseAttributeUpdate(data)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if upd.NodeID != 8 {
		t.Errorf("expected nodeID 8, got %d", upd.NodeID)
	}
	if upd.Value != false {
		t.Errorf("expected value false, got %v", upd.Value)
	}
}

func TestParseAttributeUpdate_TooFewElements(t *testing.T) {
	data := json.RawMessage(`[1, "path"]`)
	_, err := ParseAttributeUpdate(data)
	if err == nil {
		t.Fatal("expected error for too few elements")
	}
}

func TestParseAttributeUpdate_InvalidFormat(t *testing.T) {
	data := json.RawMessage(`"not an array"`)
	_, err := ParseAttributeUpdate(data)
	if err == nil {
		t.Fatal("expected error for non-array")
	}
}

func TestReadLoop_EventDispatch(t *testing.T) {
	eventReceived := make(chan Event, 1)

	upgrader := websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close()

		// Send server info
		conn.WriteJSON(ServerInfo{FabricID: 1, SDKVersion: "test"})

		// Wait a bit then send an event
		time.Sleep(50 * time.Millisecond)
		conn.WriteJSON(map[string]interface{}{
			"event": "attribute_updated",
			"data":  []interface{}{1, "1/69/0", true},
		})

		// Keep connection open
		time.Sleep(200 * time.Millisecond)
	}))
	defer srv.Close()

	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http")
	client := NewClient(wsURL)
	client.OnEvent(func(evt Event) {
		eventReceived <- evt
	})

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	if err := client.Connect(ctx); err != nil {
		t.Fatal(err)
	}
	defer client.Close()

	go client.ReadLoop(ctx)

	select {
	case evt := <-eventReceived:
		if evt.Type != EventAttributeUpdated {
			t.Errorf("expected attribute_updated, got %q", evt.Type)
		}
		upd, err := ParseAttributeUpdate(evt.Data)
		if err != nil {
			t.Fatalf("parse failed: %v", err)
		}
		if upd.NodeID != 1 || upd.Path != "1/69/0" || upd.Value != true {
			t.Errorf("unexpected update: %+v", upd)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for event")
	}
}
