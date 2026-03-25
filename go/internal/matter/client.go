package matter

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"
)

// Event types from matterjs-server
const (
	EventAttributeUpdated = "attribute_updated"
	EventNodeAdded        = "node_added"
	EventNodeUpdated      = "node_updated"
	EventNodeRemoved      = "node_removed"
	EventEndpointAdded    = "endpoint_added"
)

// ServerInfo is the initial message from matterjs-server
type ServerInfo struct {
	FabricID             int    `json:"fabric_id"`
	CompressedFabricID   uint64 `json:"compressed_fabric_id"`
	FabricIndex          int    `json:"fabric_index"`
	SchemaVersion        int    `json:"schema_version"`
	SDKVersion           string `json:"sdk_version"`
	BluetoothEnabled     bool   `json:"bluetooth_enabled"`
	ThreadCredentialsSet bool   `json:"thread_credentials_set"`
}

// WSMessage is a WebSocket request/response envelope
type WSMessage struct {
	MessageID string          `json:"message_id"`
	Command   string          `json:"command,omitempty"`
	Args      json.RawMessage `json:"args,omitempty"`
	Result    json.RawMessage `json:"result,omitempty"`
	ErrorCode int             `json:"error_code,omitempty"`
	Details   string          `json:"details,omitempty"`
}

// Event is an attribute change or node event
type Event struct {
	Type string          `json:"event"`
	Data json.RawMessage `json:"data"`
}

// AttributeUpdate represents [nodeID, path, value]
type AttributeUpdate struct {
	NodeID int
	Path   string
	Value  interface{}
}

// Node represents a commissioned Matter node
type Node struct {
	NodeID           int                    `json:"node_id"`
	DateCommissioned string                 `json:"date_commissioned"`
	Available        bool                   `json:"available"`
	IsBridge         bool                   `json:"is_bridge"`
	Attributes       map[string]interface{} `json:"attributes"`
	MatterVersion    string                 `json:"matter_version"`
}

// EventHandler is called for each incoming event
type EventHandler func(event Event)

// pendingReq tracks a command waiting for response
type pendingReq struct {
	ch chan json.RawMessage // receives raw response
}

// Client connects to matterjs-server WebSocket.
// Single read loop dispatches responses and events.
type Client struct {
	url     string
	conn    *websocket.Conn
	writeMu sync.Mutex // protects conn.WriteJSON
	msgID   atomic.Int64
	info    *ServerInfo
	handler EventHandler

	// Pending command responses
	pendingMu sync.Mutex
	pending   map[string]*pendingReq
}

func NewClient(url string) *Client {
	return &Client{
		url:     url,
		pending: make(map[string]*pendingReq),
	}
}

func (c *Client) OnEvent(h EventHandler) {
	c.handler = h
}

// Connect establishes the WebSocket connection
func (c *Client) Connect(ctx context.Context) error {
	dialer := websocket.Dialer{
		HandshakeTimeout: 10 * time.Second,
	}
	conn, _, err := dialer.DialContext(ctx, c.url+"/ws", nil)
	if err != nil {
		return fmt.Errorf("matter ws connect: %w", err)
	}
	c.conn = conn

	// Disable read deadline — the read loop runs forever
	c.conn.SetReadDeadline(time.Time{})

	// Read server info (first message)
	var info ServerInfo
	if err := conn.ReadJSON(&info); err != nil {
		conn.Close()
		return fmt.Errorf("matter ws server info: %w", err)
	}
	c.info = &info
	log.Printf("[matter] connected: %s (fabric=%d, ble=%v, thread=%v)", info.SDKVersion, info.FabricID, info.BluetoothEnabled, info.ThreadCredentialsSet)
	return nil
}

func (c *Client) Info() *ServerInfo {
	return c.info
}

func (c *Client) nextID() string {
	return fmt.Sprintf("ha-%d", c.msgID.Add(1))
}

// send sends a command and registers a pending response channel
func (c *Client) send(command string, args interface{}) (string, chan json.RawMessage, error) {
	id := c.nextID()
	ch := make(chan json.RawMessage, 1)

	c.pendingMu.Lock()
	c.pending[id] = &pendingReq{ch: ch}
	c.pendingMu.Unlock()

	c.writeMu.Lock()
	msg := map[string]interface{}{
		"message_id": id,
		"command":    command,
	}
	if args != nil {
		msg["args"] = args
	}
	err := c.conn.WriteJSON(msg)
	c.writeMu.Unlock()

	if err != nil {
		c.pendingMu.Lock()
		delete(c.pending, id)
		c.pendingMu.Unlock()
		return "", nil, fmt.Errorf("matter ws send %s: %w", command, err)
	}
	return id, ch, nil
}

// waitResponse waits for a command response with timeout
func (c *Client) waitResponse(id string, ch chan json.RawMessage, timeout time.Duration) (json.RawMessage, error) {
	defer func() {
		c.pendingMu.Lock()
		delete(c.pending, id)
		c.pendingMu.Unlock()
	}()

	select {
	case raw := <-ch:
		return raw, nil
	case <-time.After(timeout):
		return nil, fmt.Errorf("matter ws timeout waiting for %s", id)
	}
}

// GetNodes returns all commissioned nodes
func (c *Client) GetNodes(ctx context.Context) ([]Node, error) {
	id, ch, err := c.send("get_nodes", nil)
	if err != nil {
		return nil, err
	}

	raw, err := c.waitResponse(id, ch, 30*time.Second)
	if err != nil {
		return nil, err
	}

	var resp WSMessage
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("get_nodes parse resp: %w", err)
	}
	if resp.ErrorCode != 0 {
		return nil, fmt.Errorf("get_nodes error %d: %s", resp.ErrorCode, resp.Details)
	}

	var nodes []Node
	if err := json.Unmarshal(resp.Result, &nodes); err != nil {
		return nil, fmt.Errorf("get_nodes parse: %w", err)
	}
	return nodes, nil
}

// CommissionWithCode commissions a device using its setup code.
// If networkOnly is true, skip BLE and use on-network (IP) commissioning only.
func (c *Client) CommissionWithCode(ctx context.Context, code string, networkOnly bool) (*Node, error) {
	args := map[string]interface{}{"code": code}
	if networkOnly {
		args["network_only"] = true
	}
	id, ch, err := c.send("commission_with_code", args)
	if err != nil {
		return nil, err
	}

	// Commission can take 120+ seconds
	raw, err := c.waitResponse(id, ch, 180*time.Second)
	if err != nil {
		return nil, err
	}

	var resp WSMessage
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("commission parse resp: %w", err)
	}
	if resp.ErrorCode != 0 {
		return nil, fmt.Errorf("commission error %d: %s", resp.ErrorCode, resp.Details)
	}

	var node Node
	if err := json.Unmarshal(resp.Result, &node); err != nil {
		return nil, fmt.Errorf("commission parse: %w", err)
	}
	log.Printf("[matter] commissioned node %d", node.NodeID)
	return &node, nil
}

// CommissionOnNetwork commissions a device using its setup PIN code and optional IP address.
// This bypasses BLE entirely — uses IP-based commissioning (CASE).
// Useful when BLE commissioning's operative reconnection fails (e.g., mDNS issues on Android).
func (c *Client) CommissionOnNetwork(ctx context.Context, pinCode int, ipAddr string) (*Node, error) {
	args := map[string]interface{}{
		"setup_pin_code": pinCode,
	}
	if ipAddr != "" {
		args["ip_addr"] = ipAddr
	}

	id, ch, err := c.send("commission_on_network", args)
	if err != nil {
		return nil, err
	}

	// On-network commission can take 60+ seconds
	raw, err := c.waitResponse(id, ch, 120*time.Second)
	if err != nil {
		return nil, err
	}

	var resp WSMessage
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("commission_on_network parse resp: %w", err)
	}
	if resp.ErrorCode != 0 {
		return nil, fmt.Errorf("commission_on_network error %d: %s", resp.ErrorCode, resp.Details)
	}

	var node Node
	if err := json.Unmarshal(resp.Result, &node); err != nil {
		return nil, fmt.Errorf("commission_on_network parse: %w", err)
	}
	log.Printf("[matter] commissioned on-network node %d", node.NodeID)
	return &node, nil
}

// StartListening subscribes to real-time events
func (c *Client) StartListening(ctx context.Context) error {
	id, ch, err := c.send("start_listening", nil)
	if err != nil {
		return err
	}

	raw, err := c.waitResponse(id, ch, 30*time.Second)
	if err != nil {
		return err
	}

	var resp WSMessage
	if err := json.Unmarshal(raw, &resp); err != nil {
		return fmt.Errorf("start_listening parse: %w", err)
	}
	if resp.ErrorCode != 0 {
		return fmt.Errorf("start_listening error %d: %s", resp.ErrorCode, resp.Details)
	}
	log.Printf("[matter] start_listening active")
	return nil
}

// SendCommand sends a Matter cluster command to a node
func (c *Client) SendCommand(ctx context.Context, nodeID int, endpointID int, clusterID int, commandName string, payload map[string]interface{}) error {
	args := map[string]interface{}{
		"node_id":      nodeID,
		"endpoint_id":  endpointID,
		"cluster_id":   clusterID,
		"command_name": commandName,
	}
	if payload != nil {
		args["payload"] = payload
	}

	id, ch, err := c.send("device_command", args)
	if err != nil {
		return err
	}

	raw, err := c.waitResponse(id, ch, 15*time.Second)
	if err != nil {
		return err
	}

	var resp WSMessage
	if err := json.Unmarshal(raw, &resp); err != nil {
		return fmt.Errorf("send_command parse: %w", err)
	}
	if resp.ErrorCode != 0 {
		return fmt.Errorf("send_command error %d: %s", resp.ErrorCode, resp.Details)
	}
	return nil
}

// SetWifiCredentials sets WiFi credentials for commissioning WiFi Matter devices
func (c *Client) SetWifiCredentials(ctx context.Context, ssid, password string) error {
	id, ch, err := c.send("set_wifi_credentials", map[string]string{
		"ssid":        ssid,
		"credentials": password,
	})
	if err != nil {
		return err
	}

	raw, err := c.waitResponse(id, ch, 10*time.Second)
	if err != nil {
		return err
	}

	var resp WSMessage
	if err := json.Unmarshal(raw, &resp); err != nil {
		return fmt.Errorf("set_wifi_credentials parse: %w", err)
	}
	if resp.ErrorCode != 0 {
		return fmt.Errorf("set_wifi_credentials error %d: %s", resp.ErrorCode, resp.Details)
	}
	return nil
}

// SetThreadDataset sets the Thread operational dataset for commissioning
func (c *Client) SetThreadDataset(ctx context.Context, dataset string) error {
	id, ch, err := c.send("set_thread_dataset", map[string]string{"dataset": dataset})
	if err != nil {
		return err
	}

	raw, err := c.waitResponse(id, ch, 10*time.Second)
	if err != nil {
		return err
	}

	var resp WSMessage
	if err := json.Unmarshal(raw, &resp); err != nil {
		return fmt.Errorf("set_thread_dataset parse: %w", err)
	}
	if resp.ErrorCode != 0 {
		return fmt.Errorf("set_thread_dataset error %d: %s", resp.ErrorCode, resp.Details)
	}
	return nil
}

// RemoveNode removes a commissioned node from the fabric
func (c *Client) RemoveNode(ctx context.Context, nodeID int) error {
	id, ch, err := c.send("remove_node", map[string]int{"node_id": nodeID})
	if err != nil {
		return err
	}

	raw, err := c.waitResponse(id, ch, 15*time.Second)
	if err != nil {
		return err
	}

	var resp WSMessage
	if err := json.Unmarshal(raw, &resp); err != nil {
		return fmt.Errorf("remove_node parse: %w", err)
	}
	if resp.ErrorCode != 0 {
		return fmt.Errorf("remove_node error %d: %s", resp.ErrorCode, resp.Details)
	}
	return nil
}

// ReadAttribute reads a device attribute by path (e.g. "1/6/0")
func (c *Client) ReadAttribute(ctx context.Context, nodeID int, attrPath string) (interface{}, error) {
	id, ch, err := c.send("read_attribute", map[string]interface{}{
		"node_id":        nodeID,
		"attribute_path": attrPath,
	})
	if err != nil {
		return nil, err
	}

	raw, err := c.waitResponse(id, ch, 10*time.Second)
	if err != nil {
		return nil, err
	}

	var resp WSMessage
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("read_attribute parse: %w", err)
	}
	if resp.ErrorCode != 0 {
		return nil, fmt.Errorf("read_attribute error %d: %s", resp.ErrorCode, resp.Details)
	}
	return resp.Result, nil
}

// PingNode checks if a node is reachable. Returns per-endpoint results.
func (c *Client) PingNode(ctx context.Context, nodeID int) (json.RawMessage, error) {
	id, ch, err := c.send("ping_node", map[string]int{"node_id": nodeID})
	if err != nil {
		return nil, err
	}

	raw, err := c.waitResponse(id, ch, 15*time.Second)
	if err != nil {
		return nil, err
	}

	var resp WSMessage
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("ping_node parse: %w", err)
	}
	if resp.ErrorCode != 0 {
		return nil, fmt.Errorf("ping_node error %d: %s", resp.ErrorCode, resp.Details)
	}

	result, err := json.Marshal(resp.Result)
	if err != nil {
		return nil, err
	}
	return result, nil
}

// InterviewNode triggers a re-interview of the node (refresh attributes)
func (c *Client) InterviewNode(ctx context.Context, nodeID int) error {
	id, ch, err := c.send("interview_node", map[string]int{"node_id": nodeID})
	if err != nil {
		return err
	}

	raw, err := c.waitResponse(id, ch, 30*time.Second)
	if err != nil {
		return err
	}

	var resp WSMessage
	if err := json.Unmarshal(raw, &resp); err != nil {
		return fmt.Errorf("interview_node parse: %w", err)
	}
	if resp.ErrorCode != 0 {
		return fmt.Errorf("interview_node error %d: %s", resp.ErrorCode, resp.Details)
	}
	return nil
}

// NodeDiagnostics retrieves diagnostic information for a node
func (c *Client) NodeDiagnostics(ctx context.Context, nodeID int) (json.RawMessage, error) {
	id, ch, err := c.send("diagnostics", map[string]int{"node_id": nodeID})
	if err != nil {
		return nil, err
	}

	raw, err := c.waitResponse(id, ch, 15*time.Second)
	if err != nil {
		return nil, err
	}

	var resp WSMessage
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("diagnostics parse: %w", err)
	}
	if resp.ErrorCode != 0 {
		return nil, fmt.Errorf("diagnostics error %d: %s", resp.ErrorCode, resp.Details)
	}

	result, err := json.Marshal(resp.Result)
	if err != nil {
		return nil, err
	}
	return result, nil
}

// CommissioningParameters holds the result of opening a commissioning window.
type CommissioningParameters struct {
	SetupPinCode    int    `json:"setup_pin_code"`
	SetupManualCode string `json:"setup_manual_code"`
	SetupQRCode     string `json:"setup_qr_code"`
}

// OpenCommissioningWindow opens a commissioning window on an already-commissioned node.
// Used for multi-admin: Flutter CHIP SDK commissions via BLE first, then opens a window
// so python-matter-server can commission the same device on its own fabric via IP.
func (c *Client) OpenCommissioningWindow(ctx context.Context, nodeID int) (*CommissioningParameters, error) {
	args := map[string]interface{}{
		"node_id": nodeID,
	}
	id, ch, err := c.send("open_commissioning_window", args)
	if err != nil {
		return nil, err
	}

	raw, err := c.waitResponse(id, ch, 30*time.Second)
	if err != nil {
		return nil, err
	}

	var resp WSMessage
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("open_commissioning_window parse resp: %w", err)
	}
	if resp.ErrorCode != 0 {
		return nil, fmt.Errorf("open_commissioning_window error %d: %s", resp.ErrorCode, resp.Details)
	}

	var params CommissioningParameters
	if err := json.Unmarshal(resp.Result, &params); err != nil {
		return nil, fmt.Errorf("open_commissioning_window parse: %w", err)
	}
	log.Printf("[matter] opened commissioning window for node %d (pin=%d)", nodeID, params.SetupPinCode)
	return &params, nil
}

// SetDefaultFabricLabel sets the fabric name shown in matterjs dashboard
func (c *Client) SetDefaultFabricLabel(ctx context.Context, label string) error {
	id, ch, err := c.send("set_default_fabric_label", map[string]string{"label": label})
	if err != nil {
		return err
	}

	raw, err := c.waitResponse(id, ch, 10*time.Second)
	if err != nil {
		return err
	}

	var resp WSMessage
	if err := json.Unmarshal(raw, &resp); err != nil {
		return fmt.Errorf("set_default_fabric_label parse: %w", err)
	}
	if resp.ErrorCode != 0 {
		return fmt.Errorf("set_default_fabric_label error %d: %s", resp.ErrorCode, resp.Details)
	}
	return nil
}

// ReadLoop is the single read goroutine. It dispatches:
//   - command responses → pending waiters
//   - events → handler
//
// Returns only on connection error.
func (c *Client) ReadLoop(ctx context.Context) error {
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		var raw json.RawMessage
		if err := c.conn.ReadJSON(&raw); err != nil {
			return fmt.Errorf("matter ws read: %w", err)
		}

		// Try as command response (has message_id)
		var msg WSMessage
		if err := json.Unmarshal(raw, &msg); err == nil && msg.MessageID != "" {
			c.pendingMu.Lock()
			p, ok := c.pending[msg.MessageID]
			c.pendingMu.Unlock()
			if ok {
				p.ch <- raw
				continue
			}
		}

		// Try as event (has "event" field)
		var evt Event
		if err := json.Unmarshal(raw, &evt); err == nil && evt.Type != "" {
			if c.handler != nil {
				c.handler(evt)
			}
			continue
		}

		// Unknown message — log and skip
		log.Printf("[matter] unknown message: %s", string(raw)[:min(200, len(raw))])
	}
}

// Close the WebSocket connection
func (c *Client) Close() error {
	if c.conn != nil {
		return c.conn.Close()
	}
	return nil
}

// ParseAttributeUpdate parses an attribute_updated event data
func ParseAttributeUpdate(data json.RawMessage) (*AttributeUpdate, error) {
	var arr []json.RawMessage
	if err := json.Unmarshal(data, &arr); err != nil {
		return nil, fmt.Errorf("attribute update: expected array: %w", err)
	}
	if len(arr) < 3 {
		return nil, fmt.Errorf("attribute update: expected 3 elements, got %d", len(arr))
	}

	var nodeID int
	if err := json.Unmarshal(arr[0], &nodeID); err != nil {
		return nil, fmt.Errorf("attribute update nodeID: %w", err)
	}

	var path string
	if err := json.Unmarshal(arr[1], &path); err != nil {
		return nil, fmt.Errorf("attribute update path: %w", err)
	}

	var value interface{}
	if err := json.Unmarshal(arr[2], &value); err != nil {
		return nil, fmt.Errorf("attribute update value: %w", err)
	}

	return &AttributeUpdate{
		NodeID: nodeID,
		Path:   path,
		Value:  value,
	}, nil
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
