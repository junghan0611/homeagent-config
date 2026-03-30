package hub

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestAPIConfig_GetDefault(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	resp, err := http.Get(srv.URL + "/api/config")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}

	var cfg RuntimeConfig
	json.NewDecoder(resp.Body).Decode(&cfg)

	// Default should be all empty
	if cfg.SLLMPrompt != "" || cfg.CloudModel != "" || cfg.AgentContext != "" {
		t.Errorf("expected empty default config, got %+v", cfg)
	}
}

func TestAPIConfig_PatchPrompt(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	// PATCH sllm_prompt
	body := `{"sllm_prompt":"새로운 시스템 프롬프트"}`
	req, _ := http.NewRequest(http.MethodPatch, srv.URL+"/api/config", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}

	var cfg RuntimeConfig
	json.NewDecoder(resp.Body).Decode(&cfg)
	if cfg.SLLMPrompt != "새로운 시스템 프롬프트" {
		t.Errorf("expected '새로운 시스템 프롬프트', got %q", cfg.SLLMPrompt)
	}

	// GET should also reflect the change
	resp2, _ := http.Get(srv.URL + "/api/config")
	defer resp2.Body.Close()
	var cfg2 RuntimeConfig
	json.NewDecoder(resp2.Body).Decode(&cfg2)
	if cfg2.SLLMPrompt != "새로운 시스템 프롬프트" {
		t.Errorf("GET after PATCH: expected '새로운 시스템 프롬프트', got %q", cfg2.SLLMPrompt)
	}
}

func TestAPIConfig_PartialUpdate(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	// Set prompt
	req1, _ := http.NewRequest(http.MethodPatch, srv.URL+"/api/config",
		strings.NewReader(`{"sllm_prompt":"prompt1","cloud_model":"gemini"}`))
	req1.Header.Set("Content-Type", "application/json")
	resp1, _ := http.DefaultClient.Do(req1)
	resp1.Body.Close()

	// Update only agent_context — prompt and cloud_model should be preserved
	req2, _ := http.NewRequest(http.MethodPatch, srv.URL+"/api/config",
		strings.NewReader(`{"agent_context":"1KB context"}`))
	req2.Header.Set("Content-Type", "application/json")
	resp2, _ := http.DefaultClient.Do(req2)
	defer resp2.Body.Close()

	var cfg RuntimeConfig
	json.NewDecoder(resp2.Body).Decode(&cfg)

	if cfg.SLLMPrompt != "prompt1" {
		t.Errorf("prompt should be preserved, got %q", cfg.SLLMPrompt)
	}
	if cfg.CloudModel != "gemini" {
		t.Errorf("cloud_model should be preserved, got %q", cfg.CloudModel)
	}
	if cfg.AgentContext != "1KB context" {
		t.Errorf("agent_context should be '1KB context', got %q", cfg.AgentContext)
	}
}

func TestAPIConfig_BadJSON(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	req, _ := http.NewRequest(http.MethodPatch, srv.URL+"/api/config", strings.NewReader("{bad"))
	req.Header.Set("Content-Type", "application/json")
	resp, _ := http.DefaultClient.Do(req)
	defer resp.Body.Close()

	if resp.StatusCode != 400 {
		t.Errorf("expected 400, got %d", resp.StatusCode)
	}
}

func TestAPIConfig_MethodNotAllowed(t *testing.T) {
	h := testHub(t)
	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	resp, _ := http.Post(srv.URL+"/api/config", "application/json", strings.NewReader("{}"))
	defer resp.Body.Close()

	if resp.StatusCode != 405 {
		t.Errorf("expected 405, got %d", resp.StatusCode)
	}
}
