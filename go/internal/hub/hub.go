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
	"sync/atomic"
	"time"

	"github.com/junghan0611/homeagent/internal/agent"
	"github.com/junghan0611/homeagent/internal/config"
	"github.com/junghan0611/homeagent/internal/matter"
)

// getOTBRDataset fetches the active Thread dataset from ot-ctl
func getOTBRDataset(otCtlPath string) (string, error) {
	out, err := exec.Command(otCtlPath, "dataset", "active", "-x").Output()
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
	Room      string                 `json:"room,omitempty"`
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

	// Commissioning guard — 동시 커미셔닝 방지
	commissioning int32 // atomic: 0=idle, 1=in_progress

	// Device aliases
	aliases map[int]DeviceAlias
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
		aliases:    loadAliases(cfg.AliasesFile),
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
		if dataset, err := getOTBRDataset(h.cfg.OtCtlPath); err != nil {
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

// Commission triggers a new device commissioning.
// Only one commissioning can run at a time — returns error if already in progress.
func (h *Hub) Commission(ctx context.Context, code string, networkOnly bool) (*DeviceState, error) {
	// 동시 커미셔닝 방지 — CAS로 0→1 전환 시도
	if !atomic.CompareAndSwapInt32(&h.commissioning, 0, 1) {
		return nil, fmt.Errorf("커미셔닝이 이미 진행 중입니다. 완료 후 다시 시도하세요")
	}
	defer atomic.StoreInt32(&h.commissioning, 0)

	node, err := h.matter.CommissionWithCode(ctx, code, networkOnly)
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
// Matter 클러스터 ID 상수
const (
	ClusterOnOff      = 6
	ClusterLevelCtrl  = 8
	ClusterColorCtrl  = 768  // 0x0300
	ClusterDoorLock   = 257  // 0x0101
	ClusterThermostat = 513  // 0x0201
)

func (h *Hub) SetOnOff(ctx context.Context, nodeID int, on bool) error {
	cmd := "off"
	if on {
		cmd = "on"
	}
	return h.matter.SendCommand(ctx, nodeID, 1, ClusterOnOff, cmd, nil)
}

// SetLevel sets brightness level (0-254) with optional transition time (100ms units)
func (h *Hub) SetLevel(ctx context.Context, nodeID int, level int, transitionTime int) error {
	payload := map[string]interface{}{
		"level":          level,
		"transitionTime": transitionTime,
	}
	return h.matter.SendCommand(ctx, nodeID, 1, ClusterLevelCtrl, "moveToLevel", payload)
}

// SetColor sets hue (0-254) and saturation (0-254) with optional transition time
func (h *Hub) SetColor(ctx context.Context, nodeID int, hue int, saturation int, transitionTime int) error {
	payload := map[string]interface{}{
		"hue":            hue,
		"saturation":     saturation,
		"transitionTime": transitionTime,
	}
	return h.matter.SendCommand(ctx, nodeID, 1, ClusterColorCtrl, "moveToHueAndSaturation", payload)
}

// SetColorTemperature sets color temperature in mireds (153-500)
func (h *Hub) SetColorTemperature(ctx context.Context, nodeID int, mireds int, transitionTime int) error {
	payload := map[string]interface{}{
		"colorTemperatureMireds": mireds,
		"transitionTime":         transitionTime,
	}
	return h.matter.SendCommand(ctx, nodeID, 1, ClusterColorCtrl, "moveToColorTemperature", payload)
}

// SetThermostat sets heating/cooling setpoint in 0.01°C units
func (h *Hub) SetThermostat(ctx context.Context, nodeID int, mode string, temperature int) error {
	var cmd string
	var payload map[string]interface{}
	switch mode {
	case "heat":
		cmd = "setpointRaiseLower"
		payload = map[string]interface{}{"mode": 0, "amount": temperature}
	case "cool":
		cmd = "setpointRaiseLower"
		payload = map[string]interface{}{"mode": 1, "amount": temperature}
	default:
		return fmt.Errorf("unknown thermostat mode: %s", mode)
	}
	return h.matter.SendCommand(ctx, nodeID, 1, ClusterThermostat, cmd, payload)
}

// LockDoor sends lock/unlock command
func (h *Hub) LockDoor(ctx context.Context, nodeID int, lock bool) error {
	cmd := "unlockDoor"
	if lock {
		cmd = "lockDoor"
	}
	return h.matter.SendCommand(ctx, nodeID, 1, ClusterDoorLock, cmd, nil)
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

	// Apply alias (overrides manufacturer name)
	if alias, ok := h.aliases[n.NodeID]; ok {
		ds.Name = alias.Name
		ds.Room = alias.Room
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

	case matter.EventNodeRemoved:
		var nodeID int
		if err := json.Unmarshal(evt.Data, &nodeID); err != nil {
			log.Printf("[hub] parse node_removed: %v", err)
			return
		}
		h.mu.Lock()
		delete(h.devices, nodeID)
		h.mu.Unlock()
		log.Printf("[hub] node %d removed (event)", nodeID)
		h.eventCh <- Event{
			Type:     "device_removed",
			DeviceID: nodeID,
		}
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
	mux.HandleFunc("/api/devices/", h.handleDeviceByID) // /api/devices/:node_id
	mux.HandleFunc("/api/commission", h.handleCommission)
	mux.HandleFunc("/api/wifi-credentials", h.handleWifiCredentials)
	mux.HandleFunc("/api/devices/command", h.handleDeviceCommand)
	mux.HandleFunc("/api/chat", h.handleChat)
	mux.HandleFunc("/api/home", h.handleHomeSurface)
	mux.HandleFunc("/api/events", h.handleSSE)
}

func (h *Hub) handleDevices(w http.ResponseWriter, r *http.Request) {
	// /api/devices 정확히 매치 (trailing slash 없음)
	if r.URL.Path != "/api/devices" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(h.Devices())
}

// handleDeviceByID handles GET/DELETE /api/devices/:node_id
func (h *Hub) handleDeviceByID(w http.ResponseWriter, r *http.Request) {
	// /api/devices/command는 별도 핸들러가 처리
	if strings.HasSuffix(r.URL.Path, "/command") {
		h.handleDeviceCommand(w, r)
		return
	}

	// /api/devices/7 → nodeID=7
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/api/devices/"), "/")
	if len(parts) == 0 || parts[0] == "" {
		http.NotFound(w, r)
		return
	}

	var nodeID int
	if _, err := fmt.Sscanf(parts[0], "%d", &nodeID); err != nil {
		http.Error(w, `{"error":"invalid node_id"}`, http.StatusBadRequest)
		return
	}

	switch r.Method {
	case http.MethodGet:
		h.mu.RLock()
		dev, ok := h.devices[nodeID]
		h.mu.RUnlock()

		if !ok {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusNotFound)
			json.NewEncoder(w).Encode(map[string]string{"error": "device not found"})
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(dev)

	case http.MethodDelete:
		h.handleDeleteDevice(w, r, nodeID)

	default:
		http.Error(w, "GET or DELETE only", http.StatusMethodNotAllowed)
	}
}

// handleDeleteDevice removes a device from the fabric
func (h *Hub) handleDeleteDevice(w http.ResponseWriter, r *http.Request, nodeID int) {
	h.mu.RLock()
	_, ok := h.devices[nodeID]
	h.mu.RUnlock()

	if !ok {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "device not found"})
		return
	}

	log.Printf("[hub] removing node %d", nodeID)
	if err := h.matter.RemoveNode(r.Context(), nodeID); err != nil {
		log.Printf("[hub] remove node %d failed: %v", nodeID, err)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}

	// Remove from local state
	h.mu.Lock()
	delete(h.devices, nodeID)
	h.mu.Unlock()

	log.Printf("[hub] node %d removed", nodeID)
	h.eventCh <- Event{
		Type:     "device_removed",
		DeviceID: nodeID,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func (h *Hub) handleWifiCredentials(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		SSID     string `json:"ssid"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if req.SSID == "" {
		http.Error(w, `{"error":"ssid required"}`, http.StatusBadRequest)
		return
	}

	if err := h.matter.SetWifiCredentials(r.Context(), req.SSID, req.Password); err != nil {
		log.Printf("[hub] set wifi credentials failed: %v", err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	log.Printf("[hub] wifi credentials set: %s", req.SSID)
	w.WriteHeader(http.StatusNoContent)
}

func (h *Hub) handleCommission(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Code        string `json:"code"`
		NetworkOnly bool   `json:"network_only"`
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
	log.Printf("[hub] commission requested: %s (network_only=%v)", req.Code, req.NetworkOnly)

	// WiFi/Thread 설정 상태 경고 (디버깅 용이)
	if h.cfg.WifiSSID == "" {
		log.Printf("[hub] ⚠️ WiFi credentials 미설정 — WiFi 디바이스 커미셔닝 시 실패할 수 있음")
	}
	if !req.NetworkOnly {
		if info := h.matter.Info(); info != nil && !info.BluetoothEnabled {
			log.Printf("[hub] ⚠️ BLE 비활성 — BLE 커미셔닝 실패 가능 (network_only=false)")
		}
	}

	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 180*time.Second)
		defer cancel()
		ds, err := h.Commission(ctx, req.Code, req.NetworkOnly)
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
		name := d.Name
		if d.Room != "" {
			name = fmt.Sprintf("[%s] %s", d.Room, d.Name)
		}
		infos = append(infos, agent.DeviceInfo{
			NodeID:    d.NodeID,
			Name:      name,
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

	// Surface updates go via SSE (chat reply already returned via HTTP)
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
		NodeID         int    `json:"node_id"`
		Command        string `json:"command"`
		Level          *int   `json:"level,omitempty"`           // 0-254
		Hue            *int   `json:"hue,omitempty"`             // 0-254
		Saturation     *int   `json:"saturation,omitempty"`      // 0-254
		ColorTemp      *int   `json:"color_temp,omitempty"`      // mireds 153-500
		Temperature    *int   `json:"temperature,omitempty"`     // 0.01°C units
		Mode           string `json:"mode,omitempty"`            // thermostat: "heat"/"cool"
		TransitionTime int    `json:"transition_time,omitempty"` // 100ms units, default 0
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	ctx := r.Context()
	var err error

	switch req.Command {
	case "on":
		err = h.SetOnOff(ctx, req.NodeID, true)
	case "off":
		err = h.SetOnOff(ctx, req.NodeID, false)

	case "set_level":
		if req.Level == nil {
			http.Error(w, `{"error":"level required (0-254)"}`, http.StatusBadRequest)
			return
		}
		err = h.SetLevel(ctx, req.NodeID, *req.Level, req.TransitionTime)

	case "set_color":
		if req.Hue == nil || req.Saturation == nil {
			http.Error(w, `{"error":"hue and saturation required (0-254)"}`, http.StatusBadRequest)
			return
		}
		err = h.SetColor(ctx, req.NodeID, *req.Hue, *req.Saturation, req.TransitionTime)

	case "set_color_temp":
		if req.ColorTemp == nil {
			http.Error(w, `{"error":"color_temp required (mireds 153-500)"}`, http.StatusBadRequest)
			return
		}
		err = h.SetColorTemperature(ctx, req.NodeID, *req.ColorTemp, req.TransitionTime)

	case "set_thermostat":
		if req.Temperature == nil || req.Mode == "" {
			http.Error(w, `{"error":"temperature and mode required"}`, http.StatusBadRequest)
			return
		}
		err = h.SetThermostat(ctx, req.NodeID, req.Mode, *req.Temperature)

	case "lock":
		err = h.LockDoor(ctx, req.NodeID, true)
	case "unlock":
		err = h.LockDoor(ctx, req.NodeID, false)

	default:
		http.Error(w, `{"error":"unknown command","commands":["on","off","set_level","set_color","set_color_temp","set_thermostat","lock","unlock"]}`, http.StatusBadRequest)
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
