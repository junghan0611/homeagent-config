// Package otbr provides a REST client for the OTBR (OpenThread Border Router) agent.
// OTBR exposes REST API on port 8081 when built with REST=ON.
package otbr

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// ThreadStatus holds the overall Thread network status
type ThreadStatus struct {
	State    string                 `json:"state"`    // "leader", "router", "child", "detached", "disabled"
	Dataset  map[string]interface{} `json:"dataset"`  // active operational dataset
	RLoc16   string                 `json:"rloc16"`   // router locator
	ExtAddr  string                 `json:"ext_addr"` // extended address
	LeaderData map[string]interface{} `json:"leader_data,omitempty"`
}

// Client talks to the OTBR REST API
type Client struct {
	baseURL    string
	httpClient *http.Client
}

// NewClient creates an OTBR REST client
func NewClient(baseURL string) *Client {
	return &Client{
		baseURL: strings.TrimRight(baseURL, "/"),
		httpClient: &http.Client{
			Timeout: 5 * time.Second,
		},
	}
}

// GetState returns the Thread state (e.g. "leader", "router", "detached")
func (c *Client) GetState() (string, error) {
	body, err := c.get("/node/state")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(body)), nil
}

// GetDataset returns the active Thread operational dataset as JSON
func (c *Client) GetDataset() (map[string]interface{}, error) {
	body, err := c.get("/node/dataset/active")
	if err != nil {
		return nil, err
	}
	var dataset map[string]interface{}
	if err := json.Unmarshal(body, &dataset); err != nil {
		return nil, fmt.Errorf("otbr dataset parse: %w", err)
	}
	return dataset, nil
}

// GetExtendedAddr returns the extended address of the node
func (c *Client) GetExtendedAddr() (string, error) {
	body, err := c.get("/node/ext-address")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(body)), nil
}

// GetRloc16 returns the RLOC16 of the node
func (c *Client) GetRloc16() (string, error) {
	body, err := c.get("/node/rloc16")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(body)), nil
}

// GetStatus returns a combined thread status
func (c *Client) GetStatus() (*ThreadStatus, error) {
	status := &ThreadStatus{}

	state, err := c.GetState()
	if err != nil {
		return nil, fmt.Errorf("otbr state: %w", err)
	}
	status.State = state

	// Remaining fields are best-effort
	if dataset, err := c.GetDataset(); err == nil {
		status.Dataset = dataset
	}
	if rloc, err := c.GetRloc16(); err == nil {
		status.RLoc16 = rloc
	}
	if ext, err := c.GetExtendedAddr(); err == nil {
		status.ExtAddr = ext
	}

	return status, nil
}

func (c *Client) get(path string) ([]byte, error) {
	resp, err := c.httpClient.Get(c.baseURL + path)
	if err != nil {
		return nil, fmt.Errorf("otbr GET %s: %w", path, err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("otbr read %s: %w", path, err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("otbr %s: HTTP %d: %s", path, resp.StatusCode, string(body))
	}

	return body, nil
}
