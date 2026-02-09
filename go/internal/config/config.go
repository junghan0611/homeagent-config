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
}

func Load() *Config {
	return &Config{
		HTTPAddr:    envOr("HOMEAGENT_HTTP_ADDR", ":8080"),
		MQTTBroker:  envOr("HOMEAGENT_MQTT_BROKER", "tcp://localhost:1883"),
		MatterWSURL: envOr("HOMEAGENT_MATTER_WS", "ws://localhost:8047"),
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
