package hub

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"

	"github.com/junghan0611/homeagent/internal/config"
	"github.com/junghan0611/homeagent/internal/matter"
)

// DeviceState represents current state of a device
type DeviceState struct {
	NodeID    int                    `json:"node_id"`
	Name      string                 `json:"name"`
	Type      string                 `json:"type"` // "contact_sensor", etc.
	Available bool                   `json:"available"`
	State     map[string]interface{} `json:"state"` // e.g. {"contact": true}
}

// Hub is the central coordinator
type Hub struct {
	cfg     *config.Config
	matter  *matter.Client
	devices map[int]*DeviceState // nodeID -> state
	mu      sync.RWMutex

	// Event subscribers
	eventCh    chan Event
	sseClients map[chan Event]struct{}
	sseMu      sync.Mutex
}

// Event is a hub-level event (abstracted from Matter/MQTT)
type Event struct {
	Type     string      `json:"type"`     // "device_state", "device_added", "commission_result"
	DeviceID int         `json:"device_id"`
	Key      string      `json:"key,omitempty"`
	Value    interface{} `json:"value,omitempty"`
}

// New creates a new Hub
func New(cfg *config.Config) *Hub {
	return &Hub{
		cfg:        cfg,
		matter:     matter.NewClient(cfg.MatterWSURL),
		devices:    make(map[int]*DeviceState),
		eventCh:    make(chan Event, 100),
		sseClients: make(map[chan Event]struct{}),
	}
}

// Run starts the hub: connect to Matter, subscribe, serve HTTP
func (h *Hub) Run(ctx context.Context) error {
	// 1. Connect to matterjs-server
	if err := h.matter.Connect(ctx); err != nil {
		return fmt.Errorf("hub: %w", err)
	}
	defer h.matter.Close()

	// 2. Set event handler
	h.matter.OnEvent(func(evt matter.Event) {
		h.handleMatterEvent(evt)
	})

	// 3. Get existing nodes
	nodes, err := h.matter.GetNodes(ctx)
	if err != nil {
		log.Printf("[hub] get_nodes failed: %v (continuing)", err)
	} else {
		for _, n := range nodes {
			h.addNode(n)
		}
		log.Printf("[hub] loaded %d existing node(s)", len(nodes))
	}

	// 4. Start listening for events
	if err := h.matter.StartListening(ctx); err != nil {
		return fmt.Errorf("hub start_listening: %w", err)
	}

	// 5. Start event broadcaster (feeds SSE clients)
	go h.eventBroadcaster(ctx)

	// 6. Listen for Matter events (blocking)
	log.Printf("[hub] listening for Matter events...")
	return h.matter.Listen(ctx)
}

// Commission triggers a new device commissioning
func (h *Hub) Commission(ctx context.Context, code string) (*DeviceState, error) {
	node, err := h.matter.CommissionWithCode(ctx, code)
	if err != nil {
		return nil, err
	}
	ds := h.addNode(*node)

	h.eventCh <- Event{
		Type:     "device_added",
		DeviceID: node.NodeID,
		Value:    ds,
	}
	return ds, nil
}

// Devices returns current device states
func (h *Hub) Devices() []DeviceState {
	h.mu.RLock()
	defer h.mu.RUnlock()

	result := make([]DeviceState, 0, len(h.devices))
	for _, d := range h.devices {
		result = append(result, *d)
	}
	return result
}

// Events returns the event channel (for A2UI streaming)
func (h *Hub) Events() <-chan Event {
	return h.eventCh
}

func (h *Hub) addNode(n matter.Node) *DeviceState {
	h.mu.Lock()
	defer h.mu.Unlock()

	ds := &DeviceState{
		NodeID:    n.NodeID,
		Available: n.Available,
		State:     make(map[string]interface{}),
	}

	// Extract device info from attributes
	if name, ok := n.Attributes["0/40/3"]; ok {
		ds.Name = fmt.Sprintf("%v", name)
	}

	// Detect device type from endpoint 1 descriptor
	if dtList, ok := n.Attributes["1/29/0"]; ok {
		if arr, ok := dtList.([]interface{}); ok && len(arr) > 0 {
			if dt, ok := arr[0].(map[string]interface{}); ok {
				if typeID, ok := dt["0"].(float64); ok {
					switch int(typeID) {
					case 21:
						ds.Type = "contact_sensor"
					case 256:
						ds.Type = "on_off_light"
					case 266:
						ds.Type = "on_off_plug"
					default:
						ds.Type = fmt.Sprintf("device_%d", int(typeID))
					}
				}
			}
		}
	}

	// Extract initial state
	if contact, ok := n.Attributes["1/69/0"]; ok {
		ds.State["contact"] = contact
	}

	h.devices[n.NodeID] = ds
	log.Printf("[hub] node %d: %s (%s) state=%v", ds.NodeID, ds.Name, ds.Type, ds.State)
	return ds
}

func (h *Hub) handleMatterEvent(evt matter.Event) {
	switch evt.Type {
	case matter.EventAttributeUpdated:
		upd, err := matter.ParseAttributeUpdate(evt.Data)
		if err != nil {
			log.Printf("[hub] parse attribute update: %v", err)
			return
		}

		h.mu.Lock()
		ds, ok := h.devices[upd.NodeID]
		if ok {
			// Map Matter paths to human-readable keys
			switch upd.Path {
			case "1/69/0": // BooleanState
				ds.State["contact"] = upd.Value
			default:
				ds.State[upd.Path] = upd.Value
			}
		}
		h.mu.Unlock()

		h.eventCh <- Event{
			Type:     "device_state",
			DeviceID: upd.NodeID,
			Key:      upd.Path,
			Value:    upd.Value,
		}

	case matter.EventNodeAdded, matter.EventNodeUpdated:
		log.Printf("[hub] %s: %s", evt.Type, string(evt.Data))
	}
}

func (h *Hub) eventBroadcaster(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case evt := <-h.eventCh:
			log.Printf("[event] %s node=%d %s=%v", evt.Type, evt.DeviceID, evt.Key, evt.Value)

			// Broadcast to SSE clients
			h.sseMu.Lock()
			for ch := range h.sseClients {
				select {
				case ch <- evt:
				default:
					// drop if client is slow
				}
			}
			h.sseMu.Unlock()
		}
	}
}

// RegisterHTTP registers hub API endpoints
func (h *Hub) RegisterHTTP(mux *http.ServeMux) {
	mux.HandleFunc("/api/devices", h.handleDevices)
	mux.HandleFunc("/api/commission", h.handleCommission)
	mux.HandleFunc("/api/events", h.handleSSE)
}

func (h *Hub) handleDevices(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(h.Devices())
}

func (h *Hub) handleCommission(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Code string `json:"code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if req.Code == "" {
		http.Error(w, `{"error":"code required"}`, http.StatusBadRequest)
		return
	}

	ds, err := h.Commission(r.Context(), req.Code)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(ds)
}

func (h *Hub) handleSSE(w http.ResponseWriter, r *http.Request) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming not supported", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("Access-Control-Allow-Origin", "*")

	ch := make(chan Event, 50)
	h.sseMu.Lock()
	h.sseClients[ch] = struct{}{}
	h.sseMu.Unlock()

	defer func() {
		h.sseMu.Lock()
		delete(h.sseClients, ch)
		h.sseMu.Unlock()
	}()

	// Send initial snapshot
	data, _ := json.Marshal(map[string]interface{}{
		"type":    "snapshot",
		"devices": h.Devices(),
	})
	fmt.Fprintf(w, "data: %s\n\n", data)
	flusher.Flush()

	ctx := r.Context()
	for {
		select {
		case <-ctx.Done():
			return
		case evt := <-ch:
			data, err := json.Marshal(evt)
			if err != nil {
				continue
			}
			fmt.Fprintf(w, "data: %s\n\n", data)
			flusher.Flush()
		}
	}
}
