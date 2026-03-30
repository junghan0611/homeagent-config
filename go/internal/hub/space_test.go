package hub

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/junghan0611/homeagent/internal/config"
)

func TestAPISpaceSummary(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	resp, err := http.Get(srv.URL + "/api/space/summary")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}

	var summary SpaceSummary
	json.NewDecoder(resp.Body).Decode(&summary)

	if summary.Timestamp == "" {
		t.Error("expected non-empty timestamp")
	}
	if len(summary.Devices) != 2 {
		t.Errorf("expected 2 devices, got %d", len(summary.Devices))
	}
	if summary.Summary == "" {
		t.Error("expected non-empty summary text")
	}
	if !strings.Contains(summary.Summary, "온라인") {
		t.Errorf("summary should contain '온라인', got: %s", summary.Summary)
	}
}

func TestAPISpaceSummary_Empty(t *testing.T) {
	h := &Hub{
		cfg:           &config.Config{},
		devices:       make(map[int]*DeviceState),
		eventCh:       make(chan Event, 10),
		sseClients:    make(map[chan Event]struct{}),
		aliases:       make(map[int]DeviceAlias),
		subscriptions: newSubscriptionManager(),
	}
	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	resp, _ := http.Get(srv.URL + "/api/space/summary")
	defer resp.Body.Close()

	var summary SpaceSummary
	json.NewDecoder(resp.Body).Decode(&summary)

	if len(summary.Devices) != 0 {
		t.Errorf("expected 0 devices, got %d", len(summary.Devices))
	}
	if !strings.Contains(summary.Summary, "등록된 디바이스가 없습니다") {
		t.Errorf("empty summary should indicate no devices, got: %s", summary.Summary)
	}
}

func TestAPISpaceSummary_MethodNotAllowed(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	resp, _ := http.Post(srv.URL+"/api/space/summary", "", nil)
	defer resp.Body.Close()

	if resp.StatusCode != 405 {
		t.Errorf("expected 405, got %d", resp.StatusCode)
	}
}

func TestDeviceStateString(t *testing.T) {
	tests := []struct {
		name     string
		device   *DeviceState
		expected string
	}{
		{"plug on", &DeviceState{Type: "on_off_plug", Available: true, State: map[string]interface{}{"on": true}}, "on"},
		{"plug off", &DeviceState{Type: "on_off_plug", Available: true, State: map[string]interface{}{"on": false}}, "off"},
		{"contact open", &DeviceState{Type: "contact_sensor", Available: true, State: map[string]interface{}{"contact": true}}, "open"},
		{"contact closed", &DeviceState{Type: "contact_sensor", Available: true, State: map[string]interface{}{"contact": false}}, "closed"},
		{"offline", &DeviceState{Type: "on_off_plug", Available: false, State: map[string]interface{}{}}, "offline"},
		{"temp", &DeviceState{Type: "temperature_sensor", Available: true, State: map[string]interface{}{"temperature": 23.5}}, "23.5°C"},
		{"humidity", &DeviceState{Type: "humidity_sensor", Available: true, State: map[string]interface{}{"humidity": 65.0}}, "65.0%"},
		{"lock locked", &DeviceState{Type: "door_lock", Available: true, State: map[string]interface{}{"lock_state": true}}, "locked"},
		{"lock unlocked", &DeviceState{Type: "door_lock", Available: true, State: map[string]interface{}{"lock_state": false}}, "unlocked"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := deviceStateString(tc.device)
			if result != tc.expected {
				t.Errorf("expected %q, got %q", tc.expected, result)
			}
		})
	}
}

func TestGenerateSummaryText_Grouped(t *testing.T) {
	devices := []SpaceDevice{
		{Name: "서재 조명", State: "on", Type: "on_off_light", Room: "서재"},
		{Name: "모니터 플러그", State: "on", Type: "on_off_plug", Room: "서재"},
		{Name: "현관문", State: "closed", Type: "contact_sensor", Room: "현관"},
	}
	text := generateSummaryText(devices, 3)

	if !strings.Contains(text, "서재") {
		t.Errorf("should contain '서재', got: %s", text)
	}
	if !strings.Contains(text, "현관") {
		t.Errorf("should contain '현관', got: %s", text)
	}
	if !strings.Contains(text, "3개 온라인") {
		t.Errorf("should contain '3개 온라인', got: %s", text)
	}
}

func TestSpaceSummary_DeviceDetails(t *testing.T) {
	h := testHub(t)
	summary := h.buildSpaceSummary()

	// testHub has 2 devices: 현관문 센서 + 거실 플러그
	found := map[string]bool{}
	for _, d := range summary.Devices {
		found[d.Name] = true
	}
	if !found["현관문 센서"] {
		t.Error("expected '현관문 센서' in devices")
	}
	if !found["거실 플러그"] {
		t.Error("expected '거실 플러그' in devices")
	}
}
