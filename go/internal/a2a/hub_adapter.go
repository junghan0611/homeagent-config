package a2a

import (
	"context"
	"encoding/json"
	"fmt"
)

// HubAdapter wraps a Hub to implement DeviceLister and ChatHandler interfaces.
// This avoids importing hub package directly (circular dependency prevention).
type HubAdapter struct {
	// DevicesFn returns device list as JSON.
	DevicesFn func() (json.RawMessage, error)
	// ChatFn processes natural language and returns response.
	ChatFn func(ctx context.Context, message string) (string, error)
}

func (a *HubAdapter) ListDevicesJSON() (json.RawMessage, error) {
	if a.DevicesFn == nil {
		return nil, fmt.Errorf("device listing not available")
	}
	return a.DevicesFn()
}

func (a *HubAdapter) Chat(ctx context.Context, message string) (string, error) {
	if a.ChatFn == nil {
		return "", fmt.Errorf("chat not available")
	}
	return a.ChatFn(ctx, message)
}
