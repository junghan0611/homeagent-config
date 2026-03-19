package config

import (
	"fmt"
	"os"
)

type Config struct {
	// HTTP 서버
	HTTPAddr string

	// MQTT 브로커
	MQTTBroker string

	// Matter WebSocket (matterjs-server)
	MatterWSURL string

	// WiFi credentials for Matter WiFi device commissioning
	WifiSSID     string
	WifiPassword string

	// LLM Agent — OpenAI-compatible endpoint (OpenRouter, DeepSeek, etc.)
	LLMEndpoint string // HOMEAGENT_LLM_ENDPOINT (기본: https://api.deepseek.com/v1)
	LLMAPIKey   string // HOMEAGENT_LLM_API_KEY → OPENROUTER_API_KEY fallback
	LLMModel    string // HOMEAGENT_LLM_MODEL

	// Device aliases
	AliasesFile string

	// Matter storage path (matterjs --storage-path)
	MatterStoragePath string

	// OTBR ot-ctl path (for Thread dataset retrieval)
	OtCtlPath string

	// OTBR REST API URL (otbr-agent REST on :8081)
	OtbrRESTURL string

	// sLLM (llama-server) for on-device inference
	SLLMEndpoint string // e.g. "http://localhost:8081" (llama-server)
	SLLMEnabled  bool   // enable sLLM fallback chain
}

func Load() *Config {
	return &Config{
		HTTPAddr:      envOr("HOMEAGENT_HTTP_ADDR", ":8080"),
		MQTTBroker:    envOr("HOMEAGENT_MQTT_BROKER", "tcp://localhost:1883"),
		MatterWSURL:   envOr("HOMEAGENT_MATTER_WS", "ws://localhost:5580"),
		WifiSSID:     os.Getenv("HOMEAGENT_WIFI_SSID"),
		WifiPassword: os.Getenv("HOMEAGENT_WIFI_PASSWORD"),
		LLMEndpoint:  envOr("HOMEAGENT_LLM_ENDPOINT", "https://api.deepseek.com/v1"),
		LLMAPIKey:    llmAPIKey(), // HOMEAGENT_LLM_API_KEY → DEEPSEEK_API_KEY → OPENROUTER_API_KEY
		LLMModel:     envOr("HOMEAGENT_LLM_MODEL", "deepseek-chat"),
		MatterStoragePath: envOr("HOMEAGENT_MATTER_STORAGE", "matter-data"),
		AliasesFile:       envOr("HOMEAGENT_ALIASES_FILE", "/opt/homeagent/aliases.json"),
		OtCtlPath:     envOr("HOMEAGENT_OT_CTL", "ot-ctl"),
		OtbrRESTURL:   envOr("HOMEAGENT_OTBR_REST", "http://localhost:8081"),
		SLLMEndpoint:  envOr("HOMEAGENT_SLLM_ENDPOINT", "http://localhost:8082"),
		SLLMEnabled:   os.Getenv("HOMEAGENT_SLLM_ENABLED") == "1",
	}
}

func (c *Config) Print() {
	fmt.Printf("  HTTP:   %s\n", c.HTTPAddr)
	fmt.Printf("  MQTT:   %s\n", c.MQTTBroker)
	fmt.Printf("  Matter: %s\n", c.MatterWSURL)
	if c.LLMAPIKey != "" {
		fmt.Printf("  LLM:    %s (%s, key: %d자)\n", c.LLMEndpoint, c.LLMModel, len(c.LLMAPIKey))
	} else {
		fmt.Printf("  LLM:    미설정 (HOMEAGENT_LLM_API_KEY 또는 OPENROUTER_API_KEY)\n")
	}
}

// llmAPIKey returns the LLM API key with fallback chain:
// HOMEAGENT_LLM_API_KEY → DEEPSEEK_API_KEY → OPENROUTER_API_KEY
func llmAPIKey() string {
	for _, key := range []string{
		"HOMEAGENT_LLM_API_KEY",
		"DEEPSEEK_API_KEY",
		"OPENROUTER_API_KEY",
	} {
		if v := os.Getenv(key); v != "" {
			return v
		}
	}
	return ""
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
