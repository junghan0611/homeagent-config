package a2a

import (
	"github.com/a2aproject/a2a-go/v2/a2a"
)

// NewAgentCard creates the HomeAgent AgentCard for A2A discovery.
func NewAgentCard(baseURL string) *a2a.AgentCard {
	return &a2a.AgentCard{
		Name:        "HomeAgent",
		Description: "On-device smart home agent — Matter/Thread devices, privacy-first, Constitutional AI",
		SupportedInterfaces: []*a2a.AgentInterface{
			a2a.NewAgentInterface(baseURL+"/a2a", a2a.TransportProtocolJSONRPC),
		},
		DefaultInputModes:  []string{"text"},
		DefaultOutputModes: []string{"text"},
		Capabilities: a2a.AgentCapabilities{
			Streaming: true, // Phase 1: SSE streaming enabled
		},
		Skills: []a2a.AgentSkill{
			{
				ID:          "device_list",
				Name:        "Device List",
				Description: "List all connected Matter/Thread smart home devices with current state",
				Tags:        []string{"iot", "matter", "smarthome"},
				Examples:    []string{"디바이스 목록", "list devices", "show all devices"},
			},
			{
				ID:          "device_status",
				Name:        "Device Status",
				Description: "Query current state of connected devices — power, brightness, temperature, contact",
				Tags:        []string{"iot", "monitoring"},
				Examples:    []string{"거실 상태", "device status", "현관문 열렸어?"},
			},
			{
				ID:          "natural_language",
				Name:        "Natural Language Control",
				Description: "Control devices using natural language via LLM agent (Gemini Flash)",
				Tags:        []string{"iot", "llm", "control"},
				Examples:    []string{"거실 불 켜줘", "turn on living room light", "온도 22도로 설정"},
			},
			{
				ID:          "space_summary",
				Name:        "Space Summary",
				Description: "Current space status summary — all device states, room grouping, text summary",
				Tags:        []string{"summary", "context", "distillation"},
				Examples:    []string{"오늘 집 상태 요약", "what happened today?", "공간 상태"},
			},
			{
				ID:          "event_subscribe",
				Name:        "Event Subscribe",
				Description: "Subscribe to device/sensor events with webhook callback",
				Tags:        []string{"webhook", "event", "subscribe"},
				Examples:    []string{"이벤트 구독", "subscribe to device changes"},
			},
			{
				ID:          "config_update",
				Name:        "Config Update",
				Description: "Update runtime config — sLLM prompt, model, context",
				Tags:        []string{"config", "repair", "context-sync"},
				Examples:    []string{"프롬프트 교체", "update sLLM model", "맥락 주입"},
			},
		},
	}
}
