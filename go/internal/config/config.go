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

	// LLM Agent
	OpenRouterKey string
	LLMModel      string

	// Device aliases
	AliasesFile string

	// OTBR ot-ctl path (for Thread dataset retrieval)
	OtCtlPath string
}

func Load() *Config {
	return &Config{
		HTTPAddr:     envOr("HOMEAGENT_HTTP_ADDR", ":8080"),
		MQTTBroker:   envOr("HOMEAGENT_MQTT_BROKER", "tcp://localhost:1883"),
		MatterWSURL:  envOr("HOMEAGENT_MATTER_WS", "ws://localhost:5580"),
		WifiSSID:      os.Getenv("HOMEAGENT_WIFI_SSID"),
		WifiPassword:  os.Getenv("HOMEAGENT_WIFI_PASSWORD"),
		OpenRouterKey: os.Getenv("OPENROUTER_API_KEY"),
		LLMModel:      envOr("HOMEAGENT_LLM_MODEL", "google/gemini-2.5-flash"),
		AliasesFile:   envOr("HOMEAGENT_ALIASES_FILE", "/opt/homeagent/aliases.json"),
		OtCtlPath:     envOr("HOMEAGENT_OT_CTL", "ot-ctl"),
	}
}

func (c *Config) Print() {
	fmt.Printf("  HTTP:   %s\n", c.HTTPAddr)
	fmt.Printf("  MQTT:   %s\n", c.MQTTBroker)
	fmt.Printf("  Matter: %s\n", c.MatterWSURL)
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
