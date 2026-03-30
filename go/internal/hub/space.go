package hub

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"strings"
	"time"
)

// SpaceDevice is a simplified device representation for space summary.
type SpaceDevice struct {
	Name  string `json:"name"`
	State string `json:"state"`
	Type  string `json:"type"`
	Room  string `json:"room,omitempty"`
}

// SpaceSummary is the response for GET /api/space/summary.
type SpaceSummary struct {
	Timestamp string        `json:"timestamp"`
	Summary   string        `json:"summary"`
	Devices   []SpaceDevice `json:"devices"`
}

// buildSpaceSummary collects device states and generates a text summary.
func (h *Hub) buildSpaceSummary() SpaceSummary {
	h.mu.RLock()
	defer h.mu.RUnlock()

	kst := time.FixedZone("KST", 9*3600)
	now := time.Now().In(kst)

	var devices []SpaceDevice
	for _, d := range h.devices {
		sd := SpaceDevice{
			Name: d.Name,
			Type: d.Type,
			Room: d.Room,
		}
		sd.State = deviceStateString(d)
		devices = append(devices, sd)
	}

	// Sort by room then name for consistent output
	sort.Slice(devices, func(i, j int) bool {
		if devices[i].Room != devices[j].Room {
			return devices[i].Room < devices[j].Room
		}
		return devices[i].Name < devices[j].Name
	})

	summary := generateSummaryText(devices, len(h.devices))

	return SpaceSummary{
		Timestamp: now.Format(time.RFC3339),
		Summary:   summary,
		Devices:   devices,
	}
}

// deviceStateString returns a human-readable state for a device.
func deviceStateString(d *DeviceState) string {
	if !d.Available {
		return "offline"
	}

	switch d.Type {
	case "on_off_plug", "on_off_light", "dimmable_light", "color_temp_light", "extended_color_light":
		if v, ok := d.State["on"]; ok {
			if v == true {
				return "on"
			}
			return "off"
		}
	case "contact_sensor":
		if v, ok := d.State["contact"]; ok {
			if v == true {
				return "open"
			}
			return "closed"
		}
	case "temperature_sensor":
		if v, ok := d.State["temperature"]; ok {
			return fmt.Sprintf("%.1f°C", toFloat(v))
		}
	case "humidity_sensor":
		if v, ok := d.State["humidity"]; ok {
			return fmt.Sprintf("%.1f%%", toFloat(v))
		}
	case "door_lock":
		if v, ok := d.State["lock_state"]; ok {
			if v == true {
				return "locked"
			}
			return "unlocked"
		}
	}
	return "unknown"
}

func toFloat(v interface{}) float64 {
	switch n := v.(type) {
	case float64:
		return n
	case int:
		return float64(n)
	default:
		return 0
	}
}

// generateSummaryText creates a template-based Korean summary.
func generateSummaryText(devices []SpaceDevice, total int) string {
	if total == 0 {
		return "등록된 디바이스가 없습니다."
	}

	// Group by room
	rooms := make(map[string][]SpaceDevice)
	for _, d := range devices {
		room := d.Room
		if room == "" {
			room = "기타"
		}
		rooms[room] = append(rooms[room], d)
	}

	var parts []string
	// Sort room names for consistent output
	roomNames := make([]string, 0, len(rooms))
	for r := range rooms {
		roomNames = append(roomNames, r)
	}
	sort.Strings(roomNames)

	for _, room := range roomNames {
		devs := rooms[room]
		var descs []string
		for _, d := range devs {
			descs = append(descs, fmt.Sprintf("%s %s", d.Name, stateKorean(d.State)))
		}
		parts = append(parts, fmt.Sprintf("%s: %s", room, strings.Join(descs, ", ")))
	}

	online := 0
	for _, d := range devices {
		if d.State != "offline" {
			online++
		}
	}

	return fmt.Sprintf("%s. 디바이스 %d개 온라인.", strings.Join(parts, ". "), online)
}

// stateKorean translates device state to Korean.
func stateKorean(state string) string {
	switch state {
	case "on":
		return "ON"
	case "off":
		return "OFF"
	case "open":
		return "열림"
	case "closed":
		return "닫힘"
	case "locked":
		return "잠김"
	case "unlocked":
		return "열림"
	case "offline":
		return "오프라인"
	default:
		return state
	}
}

// handleSpaceSummary handles GET /api/space/summary.
func (h *Hub) handleSpaceSummary(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET only", http.StatusMethodNotAllowed)
		return
	}

	summary := h.buildSpaceSummary()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(summary)
}
