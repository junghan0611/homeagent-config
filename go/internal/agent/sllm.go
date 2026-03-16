package agent

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"
)

// SLLMConfig configures the on-device sLLM (llama-server).
type SLLMConfig struct {
	Endpoint string // e.g. "http://localhost:8082"
	Enabled  bool
}

// sllmClient wraps HTTP calls to llama-server's OpenAI-compatible API.
type sllmClient struct {
	endpoint string
	client   *http.Client
}

func newSLLMClient(endpoint string) *sllmClient {
	return &sllmClient{
		endpoint: endpoint,
		client:   &http.Client{Timeout: 15 * time.Second},
	}
}

// sllmRequest is OpenAI-compatible chat completion request.
type sllmRequest struct {
	Messages    []sllmMessage `json:"messages"`
	Temperature float64       `json:"temperature"`
	MaxTokens   int           `json:"max_tokens"`
}

type sllmMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// sllmResponse is OpenAI-compatible chat completion response.
type sllmResponse struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
	Usage struct {
		CompletionTokens int `json:"completion_tokens"`
	} `json:"usage"`
}

const sllmSystemPrompt = `당신은 스마트홈 IoT 에이전트입니다. 사용자의 자연어 명령을 JSON으로 변환하세요.

출력 형식 (JSON만, 설명 없이):
{"action": "on|off|set_level|set_color|set_color_temp|set_thermostat|lock|unlock|query|list|summary|scene", "target": "방이름|default|all", "device_type": "light|plug|sensor|contact_sensor|lock|thermostat|all", "params": {...}}

예시:
입력: "거실 불 켜줘"
출력: {"action": "on", "target": "거실", "device_type": "light"}

입력: "온도 22도로"
출력: {"action": "set_thermostat", "target": "default", "device_type": "thermostat", "params": {"temperature": 22}}`

// IntentResult is the parsed sLLM intent.
type IntentResult struct {
	Action     string                 `json:"action"`
	Target     string                 `json:"target"`
	DeviceType string                 `json:"device_type"`
	Params     map[string]interface{} `json:"params,omitempty"`
}

// ParseIntent calls llama-server to parse a natural language command into a structured intent.
// Returns nil, nil if sLLM is unavailable or fails (caller should fallback to cloud LLM).
func (s *sllmClient) ParseIntent(ctx context.Context, userMsg string) (*IntentResult, error) {
	reqBody := sllmRequest{
		Messages: []sllmMessage{
			{Role: "system", Content: sllmSystemPrompt},
			{Role: "user", Content: userMsg},
		},
		Temperature: 0,
		MaxTokens:   80,
	}

	body, _ := json.Marshal(reqBody)
	url := s.endpoint + "/v1/chat/completions"
	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("sllm request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	t0 := time.Now()
	resp, err := s.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("sllm call: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("sllm read: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("sllm status %d: %s", resp.StatusCode, string(respBody))
	}

	var sResp sllmResponse
	if err := json.Unmarshal(respBody, &sResp); err != nil {
		return nil, fmt.Errorf("sllm parse: %w", err)
	}

	if len(sResp.Choices) == 0 {
		return nil, fmt.Errorf("sllm: no choices")
	}

	content := sResp.Choices[0].Message.Content
	elapsed := time.Since(t0)
	log.Printf("[sllm] response (%s, %d tokens): %s", elapsed.Round(time.Millisecond), sResp.Usage.CompletionTokens, content)

	// Parse JSON from response
	intent, err := extractIntent(content)
	if err != nil {
		return nil, fmt.Errorf("sllm json: %w", err)
	}

	return intent, nil
}

// extractIntent tries to parse JSON from LLM output (may contain extra text).
func extractIntent(text string) (*IntentResult, error) {
	// Find first { and matching }
	start := -1
	for i, c := range text {
		if c == '{' {
			start = i
			break
		}
	}
	if start == -1 {
		return nil, fmt.Errorf("no JSON found in: %q", text)
	}

	depth := 0
	for i := start; i < len(text); i++ {
		switch text[i] {
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				var intent IntentResult
				if err := json.Unmarshal([]byte(text[start:i+1]), &intent); err != nil {
					return nil, fmt.Errorf("json unmarshal: %w", err)
				}
				return &intent, nil
			}
		}
	}
	return nil, fmt.Errorf("incomplete JSON in: %q", text)
}

// Healthy checks if llama-server is reachable.
func (s *sllmClient) Healthy(ctx context.Context) bool {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()

	req, _ := http.NewRequestWithContext(ctx, "GET", s.endpoint+"/health", nil)
	resp, err := s.client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	return resp.StatusCode == http.StatusOK
}
