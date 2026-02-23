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
		cfg.Model = "google/gemini-2.5-flash"
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

// SurfaceUpdate is an A2UI surface update
type SurfaceUpdate struct {
	SurfaceID  string      `json:"surfaceId"`
	Components interface{} `json:"components"`
}

// ChatResult is the agent's response
type ChatResult struct {
	Reply   string          `json:"reply"`
	Actions []Action        `json:"actions,omitempty"`
	Surface *SurfaceUpdate  `json:"surface,omitempty"`
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
	sb.WriteString("## A2UI 동적 UI (선택)\n")
	sb.WriteString("상태 요약이나 대시보드 요청 시 ```surface 블록으로 UI JSON을 생성하세요:\n")
	sb.WriteString("```surface\n")
	sb.WriteString(`{"surfaceId":"main","components":[`)
	sb.WriteString("\n")
	sb.WriteString(`  {"type":"Card","props":{"variant":"outlined"},"children":[`)
	sb.WriteString("\n")
	sb.WriteString(`    {"type":"Text","props":{"variant":"h5","text":"제목"}},`)
	sb.WriteString("\n")
	sb.WriteString(`    {"type":"Text","props":{"variant":"body","text":"내용"}}`)
	sb.WriteString("\n  ]}")
	sb.WriteString("\n]}\n```\n\n")
	sb.WriteString("사용 가능한 컴포넌트:\n")
	sb.WriteString("- Text: {variant: \"h3\"/\"h5\"/\"body\"/\"caption\", text: \"...\"}\n")
	sb.WriteString("- Card: {variant: \"outlined\"/\"elevated\", children: [...]}\n")
	sb.WriteString("- Row: {gap: 8, children: [...]}\n")
	sb.WriteString("- Column: {gap: 8, children: [...]}\n")
	sb.WriteString("- Icon: {name: \"door\"/\"plug\"/\"warning\"/\"check\", size: 24, color: \"#hex\"}\n")
	sb.WriteString("- Divider: {}\n")
	sb.WriteString("- Button: {label: \"텍스트\", variant: \"filled\"/\"outlined\", actionId: \"id\"}\n\n")
	sb.WriteString("## 규칙\n")
	sb.WriteString("- 디바이스 제어 시 반드시 ```action 블록에 JSON 포함\n")
	sb.WriteString("- 제어 가능한 디바이스가 1개뿐이면 확인 없이 바로 실행 (절대 되묻지 않기)\n")
	sb.WriteString("- 이름에 [방이름]이 있으면 방이름으로 부르기 (예: '현관문 열려있어?')\n")
	sb.WriteString("- 상태 대시보드/요약 요청 시 ```surface 블록 포함\n")
	sb.WriteString("- 일반 대화는 텍스트만 응답 (surface 불필요)\n")
	sb.WriteString("- contact_sensor는 읽기 전용 (제어 불가)\n")
	sb.WriteString("- 간결하게 한국어로 응답 (1~2문장)\n")
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

// EventContext for reactive agent
type EventContext struct {
	DeviceName string `json:"device_name"`
	DeviceType string `json:"device_type"`
	EventKey   string `json:"event_key"`
	EventValue string `json:"event_value"`
	TimeKST    string `json:"time_kst"`
}

var actionBlockRe = regexp.MustCompile("(?s)```action\\s*\\n(.+?)\\n```")
var surfaceBlockRe = regexp.MustCompile("(?s)```surface\\s*\\n(.+?)\\n```")

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

	// Extract surface blocks
	surfaceMatches := surfaceBlockRe.FindAllStringSubmatch(content, 1)
	for _, m := range surfaceMatches {
		var su SurfaceUpdate
		if err := json.Unmarshal([]byte(m[1]), &su); err == nil {
			result.Surface = &su
		} else {
			log.Printf("[agent] surface parse error: %v", err)
		}
	}

	// Remove action + surface blocks from reply text
	reply := actionBlockRe.ReplaceAllString(content, "")
	reply = surfaceBlockRe.ReplaceAllString(reply, "")
	result.Reply = strings.TrimSpace(reply)

	return result, nil
}

func (a *Agent) buildEventPrompt(evt EventContext, devices []DeviceInfo) string {
	var sb strings.Builder
	sb.WriteString("당신은 HomeAgent, 스마트홈 이벤트 판단 에이전트입니다.\n\n")
	sb.WriteString("## 이벤트 발생\n")
	sb.WriteString(fmt.Sprintf("- 시각: %s\n", evt.TimeKST))
	sb.WriteString(fmt.Sprintf("- 디바이스: %s (%s)\n", evt.DeviceName, evt.DeviceType))
	sb.WriteString(fmt.Sprintf("- 변경: %s = %s\n\n", evt.EventKey, evt.EventValue))
	sb.WriteString("## 전체 디바이스 상태\n")
	for _, d := range devices {
		sb.WriteString(fmt.Sprintf("- Node %d: %s (%s) → %s\n", d.NodeID, d.Name, d.Type, d.StateDesc))
	}
	sb.WriteString("\n## 가능한 액션\n")
	sb.WriteString("on_off_plug/on_off_light만 제어 가능:\n")
	sb.WriteString("```action\n{\"action\":\"on\",\"node_id\":N}\n```\n\n")
	sb.WriteString("## 판단 규칙\n")
	sb.WriteString("- 22:00~06:00 사이 문 열림 → ⚠️ 경고 알림\n")
	sb.WriteString("- 낮 시간 문 열림/닫힘 → 📋 간결한 상태 안내\n")
	sb.WriteString("- 플러그/조명 상태 변경 → 📋 간결한 상태 안내\n")
	sb.WriteString("- 필요시 연관 디바이스 자동 제어 가능 (```action 블록 사용)\n")
	sb.WriteString("- 한 줄~두 줄 이내로 간결하게 한국어 응답\n")
	sb.WriteString("- 불필요한 알림은 하지 마세요 (\"ignore\"만 응답)\n")
	return sb.String()
}

// ReactToEvent evaluates a device event and returns agent response (or nil to ignore)
func (a *Agent) ReactToEvent(ctx context.Context, evt EventContext, devices []DeviceInfo) (*ChatResult, error) {
	sysPrompt := a.buildEventPrompt(evt, devices)

	reqBody := openRouterReq{
		Model: a.cfg.Model,
		Messages: []openRouterMsg{
			{Role: "system", Content: sysPrompt},
			{Role: "user", Content: fmt.Sprintf("%s의 %s이(가) %s = %s", evt.TimeKST, evt.DeviceName, evt.EventKey, evt.EventValue)},
		},
		MaxToks: 200,
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
	log.Printf("[agent-event] LLM response: %s", content)

	// "ignore" means no notification needed
	if strings.TrimSpace(strings.ToLower(content)) == "ignore" {
		return nil, nil
	}

	result := &ChatResult{}
	matches := actionBlockRe.FindAllStringSubmatch(content, -1)
	for _, m := range matches {
		var act Action
		if err := json.Unmarshal([]byte(m[1]), &act); err == nil {
			result.Actions = append(result.Actions, act)
		}
	}

	reply := actionBlockRe.ReplaceAllString(content, "")
	result.Reply = strings.TrimSpace(reply)
	return result, nil
}
