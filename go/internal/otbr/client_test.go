package otbr

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func mockOTBR(t *testing.T) *httptest.Server {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("/node/state", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("leader\n"))
	})
	mux.HandleFunc("/node/dataset/active", func(w http.ResponseWriter, r *http.Request) {
		dataset := map[string]interface{}{
			"NetworkName": "OpenThread-1234",
			"Channel":     float64(15),
			"PanId":       "0x1234",
		}
		json.NewEncoder(w).Encode(dataset)
	})
	mux.HandleFunc("/node/ext-address", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("dead00beef00cafe\n"))
	})
	mux.HandleFunc("/node/rloc16", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("0x0400\n"))
	})
	return httptest.NewServer(mux)
}

func TestGetState(t *testing.T) {
	srv := mockOTBR(t)
	defer srv.Close()

	c := NewClient(srv.URL)
	state, err := c.GetState()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if state != "leader" {
		t.Errorf("expected 'leader', got %q", state)
	}
}

func TestGetDataset(t *testing.T) {
	srv := mockOTBR(t)
	defer srv.Close()

	c := NewClient(srv.URL)
	dataset, err := c.GetDataset()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if dataset["NetworkName"] != "OpenThread-1234" {
		t.Errorf("expected NetworkName 'OpenThread-1234', got %v", dataset["NetworkName"])
	}
	if dataset["Channel"] != float64(15) {
		t.Errorf("expected Channel 15, got %v", dataset["Channel"])
	}
}

func TestGetExtendedAddr(t *testing.T) {
	srv := mockOTBR(t)
	defer srv.Close()

	c := NewClient(srv.URL)
	addr, err := c.GetExtendedAddr()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if addr != "dead00beef00cafe" {
		t.Errorf("expected 'dead00beef00cafe', got %q", addr)
	}
}

func TestGetStatus(t *testing.T) {
	srv := mockOTBR(t)
	defer srv.Close()

	c := NewClient(srv.URL)
	status, err := c.GetStatus()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status.State != "leader" {
		t.Errorf("expected state 'leader', got %q", status.State)
	}
	if status.RLoc16 != "0x0400" {
		t.Errorf("expected rloc16 '0x0400', got %q", status.RLoc16)
	}
	if status.Dataset == nil {
		t.Error("expected dataset to be non-nil")
	}
}

func TestGetState_ConnectionRefused(t *testing.T) {
	c := NewClient("http://localhost:1") // port 1 — connection refused
	_, err := c.GetState()
	if err == nil {
		t.Fatal("expected error for unreachable OTBR")
	}
}

func TestGetState_HTTPError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte("internal error"))
	}))
	defer srv.Close()

	c := NewClient(srv.URL)
	_, err := c.GetState()
	if err == nil {
		t.Fatal("expected error for HTTP 500")
	}
}

func TestGetStatus_PartialFailure(t *testing.T) {
	// Server only responds to /node/state, others 404
	mux := http.NewServeMux()
	mux.HandleFunc("/node/state", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("router\n"))
	})
	// /node/dataset/active → 404
	// /node/ext-address → 404
	// /node/rloc16 → 404
	srv := httptest.NewServer(mux)
	defer srv.Close()

	c := NewClient(srv.URL)
	status, err := c.GetStatus()
	if err != nil {
		t.Fatalf("GetStatus should not fail if state succeeds: %v", err)
	}
	if status.State != "router" {
		t.Errorf("expected state 'router', got %q", status.State)
	}
	// dataset/rloc/ext should be empty but not cause error
	if status.Dataset != nil {
		t.Logf("dataset unexpectedly present: %v (this is OK if 404 returns valid JSON)", status.Dataset)
	}
}

func TestGetDataset_InvalidJSON(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("not json"))
	}))
	defer srv.Close()

	c := NewClient(srv.URL)
	_, err := c.GetDataset()
	if err == nil {
		t.Fatal("expected error for invalid JSON")
	}
}

func TestClient_Timeout(t *testing.T) {
	// Server that delays longer than client timeout
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(2 * time.Second)
		w.Write([]byte("too late"))
	}))
	defer srv.Close()

	c := NewClient(srv.URL)
	c.httpClient.Timeout = 100 * time.Millisecond // very short timeout for test

	_, err := c.GetState()
	if err == nil {
		t.Fatal("expected timeout error")
	}
}
