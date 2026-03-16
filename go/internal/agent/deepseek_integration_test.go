package agent

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"
)

// TestDeepSeekIntegration은 실제 DeepSeek API를 호출합니다.
// DEEPSEEK_API_KEY 환경변수가 있을 때만 실행됩니다.
func TestDeepSeekIntegration(t *testing.T) {
	key := os.Getenv("DEEPSEEK_API_KEY")
	if key == "" {
		t.Skip("DEEPSEEK_API_KEY not set — skipping integration test")
	}

	ag := New(Config{
		Endpoint: "https://api.deepseek.com/v1",
		APIKey:   key,
		Model:    "deepseek-chat",
	})

	devices := []DeviceInfo{
		{NodeID: 8, Name: "거실 플러그", Type: "on_off_plug", Available: true, StateDesc: "켜짐 (on)"},
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	result, err := ag.Chat(ctx, "플러그 꺼줘", devices)
	if err != nil {
		t.Fatalf("DeepSeek chat failed: %v", err)
	}

	t.Logf("Reply: %q", result.Reply)
	t.Logf("Actions: %d", len(result.Actions))

	// DeepSeek는 action만 반환하고 reply를 비울 수 있음 — 둘 중 하나만 있으면 성공
	if result.Reply == "" && len(result.Actions) == 0 {
		t.Error("expected reply or actions, got neither")
	}

	if len(result.Actions) > 0 {
		act := result.Actions[0]
		t.Logf("Action: %s node %d", act.ActionType, act.NodeID)
		if act.ActionType != "off" {
			t.Errorf("expected action 'off', got %q", act.ActionType)
		}
		if act.NodeID != 8 {
			t.Errorf("expected node_id 8, got %d", act.NodeID)
		}
	}
}

// TestOpenRouterIntegration은 기존 OpenRouter도 여전히 동작하는지 확인합니다.
func TestOpenRouterIntegration(t *testing.T) {
	key := os.Getenv("OPENROUTER_API_KEY")
	if key == "" {
		t.Skip("OPENROUTER_API_KEY not set — skipping integration test")
	}

	ag := New(Config{
		Endpoint: "https://openrouter.ai/api/v1",
		APIKey:   key,
		Model:    "google/gemini-2.5-flash",
	})

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	result, err := ag.Chat(ctx, "안녕", []DeviceInfo{})
	if err != nil {
		t.Fatalf("OpenRouter chat failed: %v", err)
	}

	if result.Reply == "" {
		t.Error("expected non-empty reply")
	}
	t.Logf("Reply: %s", result.Reply)
}

// TestLLMEndpointConfig는 Endpoint가 올바르게 설정되는지 확인합니다.
func TestLLMEndpointConfig(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"", "https://api.deepseek.com/v1"},                            // 기본값
		{"https://api.deepseek.com/v1", "https://api.deepseek.com/v1"}, // 명시
		{"https://openrouter.ai/api/v1", "https://openrouter.ai/api/v1"},
		{"http://localhost:11434/v1", "http://localhost:11434/v1"}, // ollama
	}
	for _, tc := range tests {
		ag := New(Config{Endpoint: tc.input, APIKey: "test"})
		if ag.cfg.Endpoint != tc.expected {
			t.Errorf("input=%q: got %q, want %q", tc.input, ag.cfg.Endpoint, tc.expected)
		}
	}
	// 기본 모델도 확인
	ag := New(Config{APIKey: "test"})
	if ag.cfg.Model != "google/gemini-2.5-flash" {
		t.Errorf("default model: got %q", ag.cfg.Model)
	}
	fmt.Println("endpoint config test done")
}
