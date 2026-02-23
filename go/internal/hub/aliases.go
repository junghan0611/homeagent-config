package hub

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
)

// DeviceAlias holds friendly name and room for a device
type DeviceAlias struct {
	Name string `json:"name"` // e.g. "현관문 센서"
	Room string `json:"room"` // e.g. "현관"
}

// loadAliases reads device aliases from a JSON file
// Format: {"1": {"name": "현관문 센서", "room": "현관"}, "8": {"name": "거실 플러그", "room": "거실"}}
func loadAliases(path string) map[int]DeviceAlias {
	aliases := make(map[int]DeviceAlias)
	if path == "" {
		return aliases
	}

	data, err := os.ReadFile(path)
	if err != nil {
		log.Printf("[aliases] file not found: %s (using device defaults)", path)
		return aliases
	}

	// Parse as map[string]DeviceAlias, convert keys to int
	var raw map[string]DeviceAlias
	if err := json.Unmarshal(data, &raw); err != nil {
		log.Printf("[aliases] parse error: %v", err)
		return aliases
	}

	for k, v := range raw {
		var nodeID int
		if _, err := fmt.Sscanf(k, "%d", &nodeID); err == nil {
			aliases[nodeID] = v
		}
	}

	log.Printf("[aliases] loaded %d device alias(es)", len(aliases))
	return aliases
}
