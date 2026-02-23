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
	CompressedFabricID   int64  `json:"compressed_fabric_id"`
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
	Path   string // "endpoint/cluster/attribute" e.g. "1/69/0"
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

// Client connects to matterjs-server WebSocket
type Client struct {
	url     string
	conn    *websocket.Conn
	mu      sync.Mutex
	msgID   atomic.Int64
	info    *ServerInfo
	handler EventHandler
}

// NewClient creates a new Matter WebSocket client
func NewClient(url string) *Client {
	return &Client{url: url}
}

// OnEvent sets the event handler
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

	// Read server info (first message)
	var info ServerInfo
	if err := conn.ReadJSON(&info); err != nil {
		conn.Close()
		return fmt.Errorf("matter ws server info: %w", err)
	}
	c.info = &info
	log.Printf("[matter] connected: %s (fabric=%d)", info.SDKVersion, info.FabricID)
	return nil
}

// ServerInfo returns the server info received on connect
func (c *Client) Info() *ServerInfo {
	return c.info
}

func (c *Client) nextID() string {
	return fmt.Sprintf("ha-%d", c.msgID.Add(1))
}

// send sends a command and returns the message ID
func (c *Client) send(command string, args interface{}) (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	id := c.nextID()
	msg := map[string]interface{}{
		"message_id": id,
		"command":    command,
	}
	if args != nil {
		msg["args"] = args
	}
	if err := c.conn.WriteJSON(msg); err != nil {
		return "", fmt.Errorf("matter ws send %s: %w", command, err)
	}
	return id, nil
}

// GetNodes returns all commissioned nodes
func (c *Client) GetNodes(ctx context.Context) ([]Node, error) {
	id, err := c.send("get_nodes", nil)
	if err != nil {
		return nil, err
	}

	// Read until we get our response
	for {
		var raw json.RawMessage
		if err := c.conn.ReadJSON(&raw); err != nil {
			return nil, fmt.Errorf("matter ws read: %w", err)
		}

		var resp WSMessage
		if err := json.Unmarshal(raw, &resp); err != nil {
			continue
		}
		if resp.MessageID != id {
			continue
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
}

// CommissionWithCode commissions a device using its setup code
func (c *Client) CommissionWithCode(ctx context.Context, code string) (*Node, error) {
	id, err := c.send("commission_with_code", map[string]string{"code": code})
	if err != nil {
		return nil, err
	}

	// Commission can take 30+ seconds
	c.conn.SetReadDeadline(time.Now().Add(120 * time.Second))
	defer c.conn.SetReadDeadline(time.Time{})

	for {
		var raw json.RawMessage
		if err := c.conn.ReadJSON(&raw); err != nil {
			return nil, fmt.Errorf("matter ws commission read: %w", err)
		}

		var resp WSMessage
		if err := json.Unmarshal(raw, &resp); err != nil {
			continue
		}
		if resp.MessageID != id {
			continue
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
}

// StartListening subscribes to real-time events
func (c *Client) StartListening(ctx context.Context) error {
	id, err := c.send("start_listening", nil)
	if err != nil {
		return err
	}

	// Wait for ack
	for {
		var raw json.RawMessage
		if err := c.conn.ReadJSON(&raw); err != nil {
			return fmt.Errorf("matter ws listen read: %w", err)
		}

		var resp WSMessage
		if err := json.Unmarshal(raw, &resp); err != nil {
			continue
		}
		if resp.MessageID == id {
			if resp.ErrorCode != 0 {
				return fmt.Errorf("start_listening error %d: %s", resp.ErrorCode, resp.Details)
			}
			log.Printf("[matter] start_listening active")
			return nil
		}
	}
}

// Listen reads events in a loop, calling the handler for each
func (c *Client) Listen(ctx context.Context) error {
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		var raw json.RawMessage
		if err := c.conn.ReadJSON(&raw); err != nil {
			return fmt.Errorf("matter ws listen: %w", err)
		}

		var evt Event
		if err := json.Unmarshal(raw, &evt); err != nil {
			continue
		}
		if evt.Type == "" {
			continue // not an event (e.g. command response)
		}

		if c.handler != nil {
			c.handler(evt)
		}
	}
}

// ParseAttributeUpdate parses an attribute_updated event data
func ParseAttributeUpdate(data json.RawMessage) (*AttributeUpdate, error) {
	// data is [nodeID, "path", value]
	var arr []json.RawMessage
	if err := json.Unmarshal(data, &arr); err != nil {
		return nil, err
	}
	if len(arr) != 3 {
		return nil, fmt.Errorf("expected 3 elements, got %d", len(arr))
	}

	var nodeID int
	if err := json.Unmarshal(arr[0], &nodeID); err != nil {
		return nil, err
	}
	var path string
	if err := json.Unmarshal(arr[1], &path); err != nil {
		return nil, err
	}
	var value interface{}
	if err := json.Unmarshal(arr[2], &value); err != nil {
		return nil, err
	}

	return &AttributeUpdate{
		NodeID: nodeID,
		Path:   path,
		Value:  value,
	}, nil
}

// Close closes the WebSocket connection
func (c *Client) Close() error {
	if c.conn != nil {
		return c.conn.Close()
	}
	return nil
}
