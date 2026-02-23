package hub

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/junghan0611/homeagent/internal/agent"
	"github.com/junghan0611/homeagent/internal/config"
	"github.com/junghan0611/homeagent/internal/matter"
)

// getOTBRDataset fetches the active Thread dataset from ot-ctl
func getOTBRDataset() (string, error) {
	out, err := exec.Command("ot-ctl", "dataset", "active", "-x").Output()
	if err != nil {
		return "", fmt.Errorf("ot-ctl: %w", err)
	}
	dataset := strings.TrimSpace(string(out))
	// ot-ctl outputs "hex\nDone" — take the first line
	lines := strings.Split(dataset, "\n")
	if len(lines) > 0 {
		dataset = strings.TrimSpace(lines[0])
	}
	return dataset, nil
}

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

	// LLM Agent
	agent     *agent.Agent
	lastEvent time.Time // debounce rapid events
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
	var ag *agent.Agent
	if cfg.OpenRouterKey != "" {
		ag = agent.New(agent.Config{
			APIKey: cfg.OpenRouterKey,
			Model:  cfg.LLMModel,
		})
		log.Printf("[hub] LLM agent enabled: %s", cfg.LLMModel)
	}

	return &Hub{
		cfg:        cfg,
		matter:     matter.NewClient(cfg.MatterWSURL),
		devices:    make(map[int]*DeviceState),
		eventCh:    make(chan Event, 100),
		sseClients: make(map[chan Event]struct{}),
		agent:      ag,
	}
}

// Run starts the hub: connect to Matter, subscribe, serve HTTP
func (h *Hub) Run(ctx context.Context) error {
	// Start event broadcaster
	go h.eventBroadcaster(ctx)

	// Connect + read loop with auto-reconnect
	for {
		err := h.connectAndListen(ctx)
		if ctx.Err() != nil {
			return ctx.Err() // graceful shutdown
		}
		log.Printf("[hub] Matter connection lost: %v — reconnecting in 5s", err)
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(5 * time.Second):
		}
	}
}

func (h *Hub) connectAndListen(ctx context.Context) error {
	// 1. Connect to matterjs-server
	if err := h.matter.Connect(ctx); err != nil {
		return fmt.Errorf("hub connect: %w", err)
	}
	defer h.matter.Close()

	// 2. Set event handler
	h.matter.OnEvent(func(evt matter.Event) {
		h.handleMatterEvent(evt)
	})

	// 3. Start read loop FIRST (goroutine) — must run before any commands
	readErr := make(chan error, 1)
	go func() {
		readErr <- h.matter.ReadLoop(ctx)
	}()

	// 3.5. Inject Thread dataset from OTBR if not set
	if info := h.matter.Info(); info != nil && !info.ThreadCredentialsSet {
		if dataset, err := getOTBRDataset(); err != nil {
			log.Printf("[hub] OTBR dataset fetch failed: %v (continuing)", err)
		} else if dataset != "" {
			if err := h.matter.SetThreadDataset(ctx, dataset); err != nil {
				log.Printf("[hub] set_thread_dataset failed: %v", err)
			} else {
				log.Printf("[hub] Thread dataset injected (%d bytes)", len(dataset)/2)
			}
		}
	}

	// 3.6. Inject WiFi credentials if configured
	if h.cfg.WifiSSID != "" {
		if err := h.matter.SetWifiCredentials(ctx, h.cfg.WifiSSID, h.cfg.WifiPassword); err != nil {
			log.Printf("[hub] set_wifi_credentials failed: %v", err)
		} else {
			log.Printf("[hub] WiFi credentials set: %s", h.cfg.WifiSSID)
		}
	}

	// 4. Get existing nodes
	nodes, err := h.matter.GetNodes(ctx)
	if err != nil {
		log.Printf("[hub] get_nodes failed: %v (continuing)", err)
	} else {
		for _, n := range nodes {
			h.addNode(n)
		}
		log.Printf("[hub] loaded %d existing node(s)", len(nodes))
	}

	// 5. Start listening for events
	if err := h.matter.StartListening(ctx); err != nil {
		return fmt.Errorf("hub start_listening: %w", err)
	}

	// 6. Wait for read loop to exit (connection lost)
	log.Printf("[hub] listening for Matter events...")
	return <-readErr
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

// SetOnOff sends on/off command to a device
func (h *Hub) SetOnOff(ctx context.Context, nodeID int, on bool) error {
	// OnOff cluster = 6, command names: "on", "off", "toggle"
	cmd := "off"
	if on {
		cmd = "on"
	}
	return h.matter.SendCommand(ctx, nodeID, 1, 6, cmd, nil)
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
	if onoff, ok := n.Attributes["1/6/0"]; ok {
		ds.State["on"] = onoff
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
			case "1/69/0": // BooleanState (contact sensor)
				ds.State["contact"] = upd.Value
			case "1/6/0": // OnOff
				ds.State["on"] = upd.Value
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

		// Trigger agent reaction (debounced, async)
		if h.agent != nil && time.Since(h.lastEvent) > 3*time.Second {
			h.lastEvent = time.Now()
			devName := ""
			devType := ""
			if ds != nil {
				devName = ds.Name
				devType = ds.Type
			}
			evtCtx := agent.EventContext{
				DeviceName: devName,
				DeviceType: devType,
				EventKey:   upd.Path,
				EventValue: fmt.Sprintf("%v", upd.Value),
				TimeKST:    time.Now().In(time.FixedZone("KST", 9*3600)).Format("15:04"),
			}
			go h.reactToEvent(evtCtx)
		}

	case matter.EventNodeAdded, matter.EventNodeUpdated:
		log.Printf("[hub] %s: %s", evt.Type, string(evt.Data))
	}
}

func (h *Hub) reactToEvent(evtCtx agent.EventContext) {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	result, err := h.agent.ReactToEvent(ctx, evtCtx, h.deviceInfos())
	if err != nil {
		log.Printf("[agent-event] error: %v", err)
		return
	}
	if result == nil {
		log.Printf("[agent-event] ignored: %s %s=%s", evtCtx.DeviceName, evtCtx.EventKey, evtCtx.EventValue)
		return
	}

	// Execute any actions
	for _, act := range result.Actions {
		switch act.ActionType {
		case "on":
			if err := h.SetOnOff(ctx, act.NodeID, true); err != nil {
				log.Printf("[agent-event] action on node %d failed: %v", act.NodeID, err)
			} else {
				log.Printf("[agent-event] executed: on node %d", act.NodeID)
			}
		case "off":
			if err := h.SetOnOff(ctx, act.NodeID, false); err != nil {
				log.Printf("[agent-event] action off node %d failed: %v", act.NodeID, err)
			} else {
				log.Printf("[agent-event] executed: off node %d", act.NodeID)
			}
		}
	}

	// Push agent message via SSE
	if result.Reply != "" {
		h.eventCh <- Event{Type: "agent_message", Value: result.Reply}
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
	mux.HandleFunc("/api/devices/command", h.handleDeviceCommand)
	mux.HandleFunc("/api/chat", h.handleChat)
	mux.HandleFunc("/api/home", h.handleHomeSurface)
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

	// Commission is long-running (60-120s). Use background context
	// so browser disconnect doesn't cancel it. Return 202 immediately.
	log.Printf("[hub] commission requested: %s", req.Code)

	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 180*time.Second)
		defer cancel()
		ds, err := h.Commission(ctx, req.Code)
		if err != nil {
			log.Printf("[hub] commission failed: %v", err)
			h.eventCh <- Event{Type: "commission_error", Key: "error", Value: err.Error()}
		} else {
			log.Printf("[hub] commission success: node %d", ds.NodeID)
		}
	}()

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	json.NewEncoder(w).Encode(map[string]string{"status": "commissioning", "code": req.Code})
}

func (h *Hub) deviceInfos() []agent.DeviceInfo {
	h.mu.RLock()
	defer h.mu.RUnlock()

	var infos []agent.DeviceInfo
	for _, d := range h.devices {
		desc := ""
		switch d.Type {
		case "contact_sensor":
			if v, ok := d.State["contact"]; ok && v == true {
				desc = "열림 (open)"
			} else {
				desc = "닫힘 (closed)"
			}
		case "on_off_plug", "on_off_light":
			if v, ok := d.State["on"]; ok && v == true {
				desc = "켜짐 (on)"
			} else {
				desc = "꺼짐 (off)"
			}
		default:
			desc = fmt.Sprintf("%v", d.State)
		}
		infos = append(infos, agent.DeviceInfo{
			NodeID:    d.NodeID,
			Name:      d.Name,
			Type:      d.Type,
			Available: d.Available,
			StateDesc: desc,
		})
	}
	return infos
}

func (h *Hub) handleChat(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}
	if h.agent == nil {
		http.Error(w, `{"error":"LLM agent not configured (set OPENROUTER_API_KEY)"}`, http.StatusServiceUnavailable)
		return
	}

	var req struct {
		Message string `json:"message"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Message == "" {
		http.Error(w, `{"error":"message required"}`, http.StatusBadRequest)
		return
	}

	result, err := h.agent.Chat(r.Context(), req.Message, h.deviceInfos())
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}

	// Execute actions
	for _, act := range result.Actions {
		switch act.ActionType {
		case "on":
			if err := h.SetOnOff(r.Context(), act.NodeID, true); err != nil {
				log.Printf("[agent] action on node %d failed: %v", act.NodeID, err)
			} else {
				log.Printf("[agent] executed: on node %d", act.NodeID)
			}
		case "off":
			if err := h.SetOnOff(r.Context(), act.NodeID, false); err != nil {
				log.Printf("[agent] action off node %d failed: %v", act.NodeID, err)
			} else {
				log.Printf("[agent] executed: off node %d", act.NodeID)
			}
		}
	}

	// Push agent message via SSE
	if result.Reply != "" {
		h.eventCh <- Event{Type: "agent_message", Value: result.Reply}
	}
	if result.Surface != nil {
		h.eventCh <- Event{Type: "surface_update", Value: result.Surface}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

func (h *Hub) handleDeviceCommand(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		NodeID  int    `json:"node_id"`
		Command string `json:"command"` // "on", "off", "toggle"
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	var err error
	switch req.Command {
	case "on":
		err = h.SetOnOff(r.Context(), req.NodeID, true)
	case "off":
		err = h.SetOnOff(r.Context(), req.NodeID, false)
	default:
		http.Error(w, `{"error":"unknown command"}`, http.StatusBadRequest)
		return
	}

	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
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
