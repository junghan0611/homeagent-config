package hub

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/junghan0611/homeagent/internal/agent"
	"github.com/junghan0611/homeagent/internal/config"
	"github.com/junghan0611/homeagent/internal/matter"
	"github.com/junghan0611/homeagent/internal/otbr"
)

// getOTBRDataset fetches the active Thread dataset from ot-ctl
func getOTBRDataset(otCtlPath string) (string, error) {
	out, err := exec.Command(otCtlPath, "dataset", "active", "-x").Output()
	if err != nil {
		return "", fmt.Errorf("ot-ctl: %w", err)
	}
	dataset := strings.TrimSpace(string(out))
	// ot-ctl outputs "hex\r\nDone\r\n" on Android — take first line, strip \r
	dataset = strings.ReplaceAll(dataset, "\r", "")
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
	otbr    *otbr.Client
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
	aliases   map[int]DeviceAlias
	startTime time.Time
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
	if cfg.LLMAPIKey != "" {
		ag = agent.New(agent.Config{
			Endpoint: cfg.LLMEndpoint,
			APIKey:   cfg.LLMAPIKey,
			Model:    cfg.LLMModel,
			SLLM: agent.SLLMConfig{
				Endpoint: cfg.SLLMEndpoint,
				Enabled:  cfg.SLLMEnabled,
			},
		})
		log.Printf("[hub] LLM agent enabled: %s (sLLM: %v)", cfg.LLMModel, cfg.SLLMEnabled)
	}

	return &Hub{
		cfg:        cfg,
		matter:     matter.NewClient(cfg.MatterWSURL),
		otbr:       otbr.NewClient(cfg.OtbrRESTURL),
		devices:    make(map[int]*DeviceState),
		eventCh:    make(chan Event, 100),
		sseClients: make(map[chan Event]struct{}),
		agent:      ag,
		aliases:    loadAliases(cfg.AliasesFile),
		startTime:  time.Now(),
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

	// 5b. Fabric label 설정 (matterjs 대시보드에 이름 표시, best-effort)
	if err := h.matter.SetDefaultFabricLabel(ctx, "HomeAgent"); err != nil {
		log.Printf("[hub] fabric label 설정 실패 (무시): %v", err)
	} else {
		log.Printf("[hub] fabric label → HomeAgent")
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

// attrMap maps Matter attribute paths to human-readable state keys.
// Used in both addNode (initial state) and handleMatterEvent (SSE updates).
var attrMap = map[string]string{
	"1/6/0":    "on",          // OnOff cluster
	"1/69/0":   "contact",     // BooleanState cluster
	"1/8/0":    "level",       // LevelControl — CurrentLevel (0-254)
	"1/768/0":  "hue",         // ColorControl — CurrentHue (0-254)
	"1/768/1":  "saturation",  // ColorControl — CurrentSaturation (0-254)
	"1/768/7":  "color_temp",  // ColorControl — ColorTemperatureMireds (153-500)
	"1/1026/0": "temperature", // TemperatureMeasurement — MeasuredValue (0.01°C)
	"1/1029/0": "humidity",    // RelativeHumidityMeasurement — MeasuredValue (0.01%)
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
					case 257:
						ds.Type = "dimmable_light"
					case 266:
						ds.Type = "on_off_plug"
					case 268:
						ds.Type = "color_temp_light"
					case 269:
						ds.Type = "extended_color_light"
					case 770:
						ds.Type = "temperature_sensor"
					case 775:
						ds.Type = "humidity_sensor"
					default:
						ds.Type = fmt.Sprintf("device_%d", int(typeID))
					}
				}
			}
		}
	}

	// Extract initial state — attribute path → state key via attrMap
	for path, key := range attrMap {
		if val, ok := n.Attributes[path]; ok {
			ds.State[key] = val
		}
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
			// Map Matter attribute path to human-readable key via attrMap
			if key, mapped := attrMap[upd.Path]; mapped {
				ds.State[key] = upd.Value
			} else {
				ds.State[upd.Path] = upd.Value
			}
		}
		h.mu.Unlock()

		// SSE key: attrMap으로 변환, 미등록 path는 raw 유지
		sseKey := upd.Path
		if mapped, ok := attrMap[upd.Path]; ok {
			sseKey = mapped
		}
		h.eventCh <- Event{
			Type:     "device_state",
			DeviceID: upd.NodeID,
			Key:      sseKey,
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

		// node_updated → available 갱신 (SED 배터리 디바이스 reconnect 반영)
		// node_added → 새 노드 자동 등록 (외부 커미셔닝 감지)
		var node matter.Node
		if err := json.Unmarshal(evt.Data, &node); err == nil && node.NodeID > 0 {
			h.mu.Lock()
			if ds, ok := h.devices[node.NodeID]; ok {
				// 기존 디바이스: available 갱신
				changed := ds.Available != node.Available
				ds.Available = node.Available
				h.mu.Unlock()
				if changed {
					log.Printf("[hub] node %d available: %v", node.NodeID, node.Available)
					h.eventCh <- Event{
						Type:     "device_state",
						DeviceID: node.NodeID,
						Key:      "available",
						Value:    node.Available,
					}
				}
			} else {
				h.mu.Unlock()
				// 새 디바이스: addNode으로 등록 (node_added)
				if evt.Type == matter.EventNodeAdded {
					ds := h.addNode(node)
					h.eventCh <- Event{
						Type:     "device_added",
						DeviceID: node.NodeID,
						Value:    ds,
					}
				}
			}
		}

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
	mux.HandleFunc("/api/commission-on-network", h.handleCommissionOnNetwork)
	mux.HandleFunc("/api/open-commissioning-window", h.handleOpenCommissioningWindow)
	mux.HandleFunc("/api/wifi-credentials", h.handleWifiCredentials)
	mux.HandleFunc("/api/wifi-info", h.handleWifiInfo)
	mux.HandleFunc("/api/devices/command", h.handleDeviceCommand)
	mux.HandleFunc("/api/chat", h.handleChat)
	mux.HandleFunc("/api/home", h.handleHomeSurface)
	mux.HandleFunc("/api/events", h.handleSSE)
	mux.HandleFunc("/api/thread/status", h.handleThreadStatus)
	mux.HandleFunc("/api/thread/dataset", h.handleThreadDataset)
	mux.HandleFunc("/api/system", h.handleSystem)

	// matterjs-server 대시보드 리다이렉트 — ws://host:5580 → http://host:5580
	mux.HandleFunc("/dashboard", h.handleDashboardRedirect)
}

func (h *Hub) handleThreadDataset(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET only", http.StatusMethodNotAllowed)
		return
	}

	dataset, err := getOTBRDataset(h.cfg.OtCtlPath)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"dataset": dataset})
}

func (h *Hub) handleThreadStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET only", http.StatusMethodNotAllowed)
		return
	}

	status, err := h.otbr.GetStatus()
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{
			"error": err.Error(),
			"hint":  "OTBR이 실행 중인지 확인하세요 (./run.sh android thread-start)",
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(status)
}

func (h *Hub) handleSystem(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET only", http.StatusMethodNotAllowed)
		return
	}

	info := map[string]interface{}{
		"version":    "0.9.0",
		"uptime":     time.Since(h.startTime).Round(time.Second).String(),
		"uptime_sec": int(time.Since(h.startTime).Seconds()),
		"devices":    len(h.Devices()),
	}

	// Thread 상태 (best-effort)
	if h.otbr != nil {
		if status, err := h.otbr.GetStatus(); err == nil {
			info["thread"] = status
		}
	}

	// LLM 설정
	if h.agent != nil {
		info["llm"] = map[string]interface{}{
			"enabled":  true,
			"endpoint": h.cfg.LLMEndpoint,
			"model":    h.cfg.LLMModel,
		}
	} else {
		info["llm"] = map[string]interface{}{"enabled": false}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(info)
}

// handleDashboardRedirect redirects to matterjs-server dashboard
// Uses the browser's request host (not cfg localhost) + matterjs port
// e.g. browser→192.168.0.162:8080/dashboard → redirect→192.168.0.162:5580
func (h *Hub) handleDashboardRedirect(w http.ResponseWriter, r *http.Request) {
	wsURL := h.cfg.MatterWSURL // e.g. "ws://localhost:5580"

	// matterjs 포트 추출
	matterPort := "5580" // default
	if idx := strings.LastIndex(wsURL, ":"); idx > 0 {
		matterPort = wsURL[idx+1:]
	}

	// 브라우저 요청의 호스트에서 IP 추출 (포트 제거)
	reqHost := r.Host
	if colonIdx := strings.LastIndex(reqHost, ":"); colonIdx > 0 {
		reqHost = reqHost[:colonIdx]
	}

	scheme := "http"
	if r.TLS != nil {
		scheme = "https"
	}

	dashURL := fmt.Sprintf("%s://%s:%s", scheme, reqHost, matterPort)
	http.Redirect(w, r, dashURL, http.StatusTemporaryRedirect)
}

func (h *Hub) handleDevices(w http.ResponseWriter, r *http.Request) {
	// /api/devices 정확히 매치 (trailing slash 없음)
	if r.URL.Path != "/api/devices" {
		http.NotFound(w, r)
		return
	}

	devices := h.Devices()

	// 쿼리 필터: ?room=거실&type=on_off_plug
	roomFilter := r.URL.Query().Get("room")
	typeFilter := r.URL.Query().Get("type")
	if roomFilter != "" || typeFilter != "" {
		var filtered []DeviceState
		for _, d := range devices {
			if roomFilter != "" && d.Room != roomFilter {
				continue
			}
			if typeFilter != "" && d.Type != typeFilter {
				continue
			}
			filtered = append(filtered, d)
		}
		devices = filtered
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(devices)
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

	// /api/devices/:id/action 라우팅
	if len(parts) > 1 {
		switch parts[1] {
		case "attributes":
			h.handleReadAttribute(w, r, nodeID)
		case "ping":
			h.handlePingNode(w, r, nodeID)
		case "interview":
			h.handleInterviewNode(w, r, nodeID)
		case "diagnostics":
			h.handleNodeDiagnostics(w, r, nodeID)
		default:
			http.NotFound(w, r)
		}
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

	case http.MethodPatch:
		h.handlePatchDevice(w, r, nodeID)

	default:
		http.Error(w, "GET, DELETE, or PATCH only", http.StatusMethodNotAllowed)
	}
}

// handlePatchDevice updates device name/room and persists to aliases.json
func (h *Hub) handlePatchDevice(w http.ResponseWriter, r *http.Request, nodeID int) {
	var req struct {
		Name *string `json:"name,omitempty"`
		Room *string `json:"room,omitempty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"잘못된 JSON 형식"}`, http.StatusBadRequest)
		return
	}

	h.mu.Lock()
	dev, ok := h.devices[nodeID]
	if !ok {
		h.mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "디바이스를 찾을 수 없습니다"})
		return
	}
	if req.Name != nil {
		dev.Name = *req.Name
	}
	if req.Room != nil {
		dev.Room = *req.Room
	}
	// aliases 내부 맵도 갱신
	h.aliases[nodeID] = DeviceAlias{Name: dev.Name, Room: dev.Room}
	h.mu.Unlock()

	// aliases.json 영속
	if err := h.saveAliases(); err != nil {
		log.Printf("[hub] aliases 저장 실패: %v", err)
	}

	// SSE 이벤트
	h.eventCh <- Event{Type: "device_updated", DeviceID: nodeID, Value: dev}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(dev)
}

// handleReadAttribute reads a device attribute by path
// GET /api/devices/:id/attributes?path=1/6/0
func (h *Hub) handleReadAttribute(w http.ResponseWriter, r *http.Request, nodeID int) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET only", http.StatusMethodNotAllowed)
		return
	}

	attrPath := r.URL.Query().Get("path")
	if attrPath == "" {
		http.Error(w, `{"error":"path 파라미터 필수 (예: ?path=1/6/0)"}`, http.StatusBadRequest)
		return
	}

	result, err := h.matter.ReadAttribute(r.Context(), nodeID, attrPath)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"node_id": nodeID,
		"path":    attrPath,
		"value":   result,
	})
}

// handlePingNode pings a device to check connectivity
// POST /api/devices/:id/ping
func (h *Hub) handlePingNode(w http.ResponseWriter, r *http.Request, nodeID int) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}

	result, err := h.matter.PingNode(r.Context(), nodeID)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write(result)
}

// handleInterviewNode triggers re-interview of a device
// POST /api/devices/:id/interview
func (h *Hub) handleInterviewNode(w http.ResponseWriter, r *http.Request, nodeID int) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}

	if err := h.matter.InterviewNode(r.Context(), nodeID); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// handleNodeDiagnostics retrieves diagnostic info for a device
// GET /api/devices/:id/diagnostics
func (h *Hub) handleNodeDiagnostics(w http.ResponseWriter, r *http.Request, nodeID int) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET only", http.StatusMethodNotAllowed)
		return
	}

	result, err := h.matter.NodeDiagnostics(r.Context(), nodeID)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write(result)
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

	// Peer 스토리지 정리 (matter-server GC 미비 workaround)
	h.cleanPeerStorage(nodeID)

	log.Printf("[hub] node %d removed", nodeID)
	h.eventCh <- Event{
		Type:     "device_removed",
		DeviceID: nodeID,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// cleanPeerStorage removes leftover peer files from matter-data
// matter-server doesn't clean up nodes.peerN.* files on remove_node
func (h *Hub) cleanPeerStorage(nodeID int) {
	storagePath := h.cfg.MatterStoragePath
	fabricDir := filepath.Join(storagePath, "server-1-fff1")
	peerPrefix := fmt.Sprintf("nodes.peer%d.", nodeID)

	entries, err := os.ReadDir(fabricDir)
	if err != nil {
		log.Printf("[hub] peer storage dir not found: %s (%v)", fabricDir, err)
		return
	}

	count := 0
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), peerPrefix) {
			if err := os.Remove(filepath.Join(fabricDir, e.Name())); err == nil {
				count++
			}
		}
	}
	if count > 0 {
		log.Printf("[hub] cleaned peer%d storage: %d files removed", nodeID, count)
	}
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

func (h *Hub) handleWifiInfo(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET only", http.StatusMethodNotAllowed)
		return
	}

	ssid := h.cfg.WifiSSID
	password := h.cfg.WifiPassword
	auto := ssid != "" && password != ""

	// 2순위: Android dumpsys wifi → 현재 연결 SSID
	if ssid == "" {
		if out, err := exec.Command("dumpsys", "wifi").Output(); err == nil {
			s := string(out)
			if idx := strings.Index(s, "SSID: \""); idx != -1 {
				start := idx + 7
				if end := strings.Index(s[start:], "\""); end > 0 {
					ssid = s[start : start+end]
				}
			}
		}
	}

	// SSID 있고 비밀번호 없으면 → WifiConfigStore.xml에서 매칭
	if ssid != "" && password == "" {
		// 1차: start.sh가 복사한 로컬 사본 (SELinux 우회)
		// 2차: 원본 (adb root에서 직접 실행 시)
		xmlPath := "/data/local/tmp/WifiConfigStore.xml"
		if _, err := os.Stat(xmlPath); err != nil {
			xmlPath = "/data/misc/apexdata/com.android.wifi/WifiConfigStore.xml"
		}
		if data, err := os.ReadFile(xmlPath); err == nil {
			content := string(data)
			target := "&quot;" + ssid + "&quot;"
			if idx := strings.Index(content, target); idx != -1 {
				rest := content[idx:]
				if pskIdx := strings.Index(rest, "PreSharedKey"); pskIdx != -1 {
					pskRest := rest[pskIdx:]
					if q1 := strings.Index(pskRest, "&quot;"); q1 != -1 {
						q1 += 6
						if q2 := strings.Index(pskRest[q1:], "&quot;"); q2 > 0 {
							password = pskRest[q1 : q1+q2]
							auto = true
						}
					}
				}
			}
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"ssid":     ssid,
		"password": password,
		"auto":     auto,
	})
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

// handleCommissionOnNetwork handles POST /api/commission-on-network
// Bypasses BLE — uses IP-based commissioning (CASE). Useful when BLE commissioning's
// operative reconnection fails (mDNS issues on Android).
func (h *Hub) handleCommissionOnNetwork(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		PinCode int    `json:"pin_code"`
		IPAddr  string `json:"ip_addr"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if req.PinCode == 0 {
		http.Error(w, `{"error":"pin_code required"}`, http.StatusBadRequest)
		return
	}

	log.Printf("[hub] commission-on-network requested: pin=%d ip=%s", req.PinCode, req.IPAddr)

	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
		defer cancel()

		if !atomic.CompareAndSwapInt32(&h.commissioning, 0, 1) {
			log.Printf("[hub] commission-on-network rejected: already in progress")
			h.eventCh <- Event{Type: "commission_error", Key: "error", Value: "커미셔닝이 이미 진행 중입니다"}
			return
		}
		defer atomic.StoreInt32(&h.commissioning, 0)

		node, err := h.matter.CommissionOnNetwork(ctx, req.PinCode, req.IPAddr)
		if err != nil {
			log.Printf("[hub] commission-on-network failed: %v", err)
			h.eventCh <- Event{Type: "commission_error", Key: "error", Value: err.Error()}
			return
		}

		ds := h.addNode(*node)
		log.Printf("[hub] commission-on-network success: node %d", ds.NodeID)
		h.eventCh <- Event{
			Type:     "device_added",
			DeviceID: node.NodeID,
			Value:    ds,
		}
	}()

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	json.NewEncoder(w).Encode(map[string]string{"status": "commissioning_on_network"})
}

// handleOpenCommissioningWindow handles POST /api/open-commissioning-window
// Opens a commissioning window on an already-commissioned node for multi-admin.
// Flutter CHIP SDK commissions via BLE first, then calls this so python-matter-server
// can add the device to its own fabric via IP.
func (h *Hub) handleOpenCommissioningWindow(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		NodeID int `json:"node_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if req.NodeID == 0 {
		http.Error(w, `{"error":"node_id required"}`, http.StatusBadRequest)
		return
	}

	log.Printf("[hub] open-commissioning-window requested: node=%d", req.NodeID)

	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()

	params, err := h.matter.OpenCommissioningWindow(ctx, req.NodeID)
	if err != nil {
		log.Printf("[hub] open-commissioning-window failed: %v", err)
		http.Error(w, fmt.Sprintf(`{"error":"%s"}`, err.Error()), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(params)
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
		if *req.Level < 0 || *req.Level > 254 {
			http.Error(w, `{"error":"level must be 0-254"}`, http.StatusBadRequest)
			return
		}
		err = h.SetLevel(ctx, req.NodeID, *req.Level, req.TransitionTime)

	case "set_color":
		if req.Hue == nil || req.Saturation == nil {
			http.Error(w, `{"error":"hue and saturation required (0-254)"}`, http.StatusBadRequest)
			return
		}
		if *req.Hue < 0 || *req.Hue > 254 || *req.Saturation < 0 || *req.Saturation > 254 {
			http.Error(w, `{"error":"hue and saturation must be 0-254"}`, http.StatusBadRequest)
			return
		}
		err = h.SetColor(ctx, req.NodeID, *req.Hue, *req.Saturation, req.TransitionTime)

	case "set_color_temp":
		if req.ColorTemp == nil {
			http.Error(w, `{"error":"color_temp required (mireds 153-500)"}`, http.StatusBadRequest)
			return
		}
		if *req.ColorTemp < 153 || *req.ColorTemp > 500 {
			http.Error(w, `{"error":"color_temp must be 153-500 mireds"}`, http.StatusBadRequest)
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
