package agent

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"regexp"
	"strings"
	"time"
)

type Config struct {
	APIKey string // OpenRouter API key
	Model  string // e.g. "google/gemini-2.0-flash-001"
}

type Agent struct {
	cfg    Config
	client *http.Client
}

func New(cfg Config) *Agent {
	if cfg.Model == "" {
		cfg.Model = "google/gemini-2.0-flash-001"
	}
	return &Agent{
		cfg:    cfg,
		client: &http.Client{Timeout: 30 * time.Second},
	}
}

// DeviceInfo for system prompt
type DeviceInfo struct {
	NodeID    int    `json:"node_id"`
	Name      string `json:"name"`
	Type      string `json:"type"`
	Available bool   `json:"available"`
	StateDesc string `json:"state_desc"`
}

// Action extracted from LLM response
type Action struct {
	ActionType string `json:"action"` // "on", "off"
	NodeID     int    `json:"node_id"`
}

// ChatResult is the agent's response
type ChatResult struct {
	Reply   string   `json:"reply"`
	Actions []Action `json:"actions,omitempty"`
}

func (a *Agent) buildSystemPrompt(devices []DeviceInfo) string {
	var sb strings.Builder
	sb.WriteString("당신은 HomeAgent, Matter 스마트홈 어시스턴트입니다.\n\n")
	sb.WriteString("## 현재 디바이스 상태\n")
	for _, d := range devices {
		sb.WriteString(fmt.Sprintf("- Node %d: %s (%s) → %s\n", d.NodeID, d.Name, d.Type, d.StateDesc))
	}
	sb.WriteString("\n## 가능한 명령\n")
	sb.WriteString("on_off_plug/on_off_light 타입만 제어 가능:\n")
	sb.WriteString("```action\n{\"action\":\"on\",\"node_id\":N}\n```\n")
	sb.WriteString("```action\n{\"action\":\"off\",\"node_id\":N}\n```\n\n")
	sb.WriteString("## 규칙\n")
	sb.WriteString("- 디바이스 제어 시 반드시 ```action 블록에 JSON 포함\n")
	sb.WriteString("- contact_sensor는 읽기 전용 (제어 불가)\n")
	sb.WriteString("- 상태 질문은 현재 데이터 기반으로 답변\n")
	sb.WriteString("- 간결하게 한국어로 응답\n")
	return sb.String()
}

type openRouterReq struct {
	Model    string          `json:"model"`
	Messages []openRouterMsg `json:"messages"`
	MaxToks  int             `json:"max_tokens"`
}

type openRouterMsg struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type openRouterResp struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

var actionBlockRe = regexp.MustCompile("(?s)```action\\s*\\n(.+?)\\n```")

func (a *Agent) Chat(ctx context.Context, userMsg string, devices []DeviceInfo) (*ChatResult, error) {
	sysPrompt := a.buildSystemPrompt(devices)

	reqBody := openRouterReq{
		Model: a.cfg.Model,
		Messages: []openRouterMsg{
			{Role: "system", Content: sysPrompt},
			{Role: "user", Content: userMsg},
		},
		MaxToks: 500,
	}

	body, _ := json.Marshal(reqBody)
	req, _ := http.NewRequestWithContext(ctx, "POST", "https://openrouter.ai/api/v1/chat/completions", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+a.cfg.APIKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := a.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("openrouter: %w", err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	var orResp openRouterResp
	if err := json.Unmarshal(respBody, &orResp); err != nil {
		return nil, fmt.Errorf("openrouter parse: %w", err)
	}
	if orResp.Error != nil {
		return nil, fmt.Errorf("openrouter: %s", orResp.Error.Message)
	}
	if len(orResp.Choices) == 0 {
		return nil, fmt.Errorf("openrouter: no choices")
	}

	content := orResp.Choices[0].Message.Content
	log.Printf("[agent] LLM response: %s", content)

	// Extract actions from ```action blocks
	result := &ChatResult{}
	matches := actionBlockRe.FindAllStringSubmatch(content, -1)
	for _, m := range matches {
		var act Action
		if err := json.Unmarshal([]byte(m[1]), &act); err == nil {
			result.Actions = append(result.Actions, act)
		}
	}

	// Remove action blocks from reply text
	reply := actionBlockRe.ReplaceAllString(content, "")
	result.Reply = strings.TrimSpace(reply)

	return result, nil
}
