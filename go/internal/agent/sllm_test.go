package agent

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestExtractIntent(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		action  string
		target  string
		wantErr bool
	}{
		{
			name:   "clean JSON",
			input:  `{"action": "on", "target": "거실", "device_type": "light"}`,
			action: "on",
			target: "거실",
		},
		{
			name:   "JSON with prefix text",
			input:  `Here is the result: {"action": "off", "target": "침실", "device_type": "plug"}`,
			action: "off",
			target: "침실",
		},
		{
			name:   "JSON with suffix",
			input:  `{"action": "set_level", "target": "default", "device_type": "light", "params": {"level": 50}} done`,
			action: "set_level",
			target: "default",
		},
		{
			name:    "no JSON",
			input:   "I don't understand",
			wantErr: true,
		},
		{
			name:    "empty",
			input:   "",
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			intent, err := extractIntent(tt.input)
			if tt.wantErr {
				if err == nil {
					t.Error("expected error, got nil")
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if intent.Action != tt.action {
				t.Errorf("action: got %q, want %q", intent.Action, tt.action)
			}
			if intent.Target != tt.target {
				t.Errorf("target: got %q, want %q", intent.Target, tt.target)
			}
		})
	}
}

func TestSLLMClientParseIntent(t *testing.T) {
	// Mock llama-server
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/health" {
			w.WriteHeader(http.StatusOK)
			return
		}
		if r.URL.Path == "/v1/chat/completions" {
			resp := map[string]interface{}{
				"choices": []map[string]interface{}{
					{
						"message": map[string]string{
							"content": `{"action": "on", "target": "거실", "device_type": "light"}`,
						},
					},
				},
				"usage": map[string]int{
					"completion_tokens": 20,
				},
			}
			json.NewEncoder(w).Encode(resp)
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()

	client := newSLLMClient(server.URL)

	// Test Healthy
	if !client.Healthy(context.Background()) {
		t.Error("expected healthy")
	}

	// Test ParseIntent
	intent, err := client.ParseIntent(context.Background(), "거실 불 켜줘")
	if err != nil {
		t.Fatalf("ParseIntent error: %v", err)
	}
	if intent.Action != "on" {
		t.Errorf("action: got %q, want %q", intent.Action, "on")
	}
	if intent.Target != "거실" {
		t.Errorf("target: got %q, want %q", intent.Target, "거실")
	}
	if intent.DeviceType != "light" {
		t.Errorf("device_type: got %q, want %q", intent.DeviceType, "light")
	}
}

func TestResolveNodeID(t *testing.T) {
	a := &Agent{}
	devices := []DeviceInfo{
		{NodeID: 1, Name: "현관문 센서", Type: "contact_sensor"},
		{NodeID: 8, Name: "거실 플러그", Type: "on_off_plug"},
		{NodeID: 10, Name: "침실 조명", Type: "dimmable_light"},
	}

	tests := []struct {
		target     string
		deviceType string
		want       int
	}{
		{"거실", "plug", 8},
		{"침실", "light", 10},
		{"현관문", "contact_sensor", 0}, // not controllable
		{"없는곳", "light", 0},
		{"default", "plug", 8},   // single plug → resolve
		{"default", "light", 10}, // single light → resolve
	}

	for _, tt := range tests {
		got := a.resolveNodeID(tt.target, tt.deviceType, devices)
		if got != tt.want {
			t.Errorf("resolveNodeID(%q, %q) = %d, want %d", tt.target, tt.deviceType, got, tt.want)
		}
	}
}

func TestChatViaSLLM(t *testing.T) {
	// Mock llama-server
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		resp := map[string]interface{}{
			"choices": []map[string]interface{}{
				{
					"message": map[string]string{
						"content": `{"action": "off", "target": "거실", "device_type": "plug"}`,
					},
				},
			},
			"usage": map[string]int{"completion_tokens": 15},
		}
		json.NewEncoder(w).Encode(resp)
	}))
	defer server.Close()

	a := New(Config{
		SLLM: SLLMConfig{Endpoint: server.URL, Enabled: true},
	})

	devices := []DeviceInfo{
		{NodeID: 8, Name: "거실 플러그", Type: "on_off_plug", Available: true, StateDesc: "켜짐"},
	}

	result, err := a.Chat(context.Background(), "거실 플러그 꺼", devices)
	if err != nil {
		t.Fatalf("Chat error: %v", err)
	}
	if len(result.Actions) != 1 {
		t.Fatalf("expected 1 action, got %d", len(result.Actions))
	}
	if result.Actions[0].ActionType != "off" {
		t.Errorf("action: got %q, want %q", result.Actions[0].ActionType, "off")
	}
	if result.Actions[0].NodeID != 8 {
		t.Errorf("nodeID: got %d, want %d", result.Actions[0].NodeID, 8)
	}
}

func TestFallbackToCloud(t *testing.T) {
	// sLLM returns "query" action → should fallback to cloud
	sllmServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		resp := map[string]interface{}{
			"choices": []map[string]interface{}{
				{
					"message": map[string]string{
						"content": `{"action": "query", "target": "거실", "device_type": "sensor"}`,
					},
				},
			},
			"usage": map[string]int{"completion_tokens": 15},
		}
		json.NewEncoder(w).Encode(resp)
	}))
	defer sllmServer.Close()

	// Cloud returns rich response
	cloudServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		resp := map[string]interface{}{
			"choices": []map[string]interface{}{
				{
					"message": map[string]string{
						"content": "현재 거실 온도는 23.5°C입니다.",
					},
				},
			},
		}
		json.NewEncoder(w).Encode(resp)
	}))
	defer cloudServer.Close()

	// Patch OpenRouter URL for test — we can't easily do this with current code
	// so just verify sLLM returns nil for query action
	a := &Agent{
		cfg:    Config{SLLM: SLLMConfig{Endpoint: sllmServer.URL, Enabled: true}},
		sllm:   newSLLMClient(sllmServer.URL),
		client: &http.Client{},
	}

	devices := []DeviceInfo{
		{NodeID: 8, Name: "거실 플러그", Type: "on_off_plug"},
	}

	// chatViaSLLM should return nil for "query" intent
	result, err := a.chatViaSLLM(context.Background(), "온도 몇 도야?", devices)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result != nil {
		t.Error("expected nil result for query intent (should fallback)")
	}
}
