package hub

import (
	"encoding/json"
	"log"
	"net/http"
)

// RuntimeConfig holds runtime-mutable configuration.
// Persisted only in memory — reset on restart (by design for Phase 4).
type RuntimeConfig struct {
	SLLMPrompt   string `json:"sllm_prompt,omitempty"`
	SLLMEndpoint string `json:"sllm_endpoint,omitempty"`
	SLLMModel    string `json:"sllm_model,omitempty"`
	CloudModel   string `json:"cloud_model,omitempty"`
	AgentContext string `json:"agent_context,omitempty"`
}

// GetRuntimeConfig returns a copy of the current runtime config.
func (h *Hub) GetRuntimeConfig() RuntimeConfig {
	h.runtimeCfgMu.RLock()
	defer h.runtimeCfgMu.RUnlock()
	return h.runtimeCfg
}

// PatchRuntimeConfig applies partial updates to runtime config.
// Only non-empty fields in the patch are applied.
func (h *Hub) PatchRuntimeConfig(patch RuntimeConfig) RuntimeConfig {
	h.runtimeCfgMu.Lock()
	defer h.runtimeCfgMu.Unlock()

	if patch.SLLMPrompt != "" {
		h.runtimeCfg.SLLMPrompt = patch.SLLMPrompt
	}
	if patch.SLLMEndpoint != "" {
		h.runtimeCfg.SLLMEndpoint = patch.SLLMEndpoint
	}
	if patch.SLLMModel != "" {
		h.runtimeCfg.SLLMModel = patch.SLLMModel
	}
	if patch.CloudModel != "" {
		h.runtimeCfg.CloudModel = patch.CloudModel
	}
	if patch.AgentContext != "" {
		h.runtimeCfg.AgentContext = patch.AgentContext
	}

	log.Printf("[config] updated: %+v", h.runtimeCfg)
	return h.runtimeCfg
}

// handleConfig handles GET /api/config and PATCH /api/config.
func (h *Hub) handleConfig(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		cfg := h.GetRuntimeConfig()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(cfg)

	case http.MethodPatch:
		var patch RuntimeConfig
		if err := json.NewDecoder(r.Body).Decode(&patch); err != nil {
			http.Error(w, `{"error":"잘못된 JSON 형식"}`, http.StatusBadRequest)
			return
		}

		updated := h.PatchRuntimeConfig(patch)
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(updated)

	default:
		http.Error(w, "GET or PATCH only", http.StatusMethodNotAllowed)
	}
}
