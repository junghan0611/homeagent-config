package hub

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// --- subscription manager unit tests ---

func TestSubscriptionManager_AddListRemove(t *testing.T) {
	sm := newSubscriptionManager()

	// Add
	sub := sm.add("device_state", "http://example.com/hook", nil)
	if sub.ID == "" {
		t.Fatal("expected non-empty ID")
	}
	if sub.EventType != "device_state" {
		t.Errorf("expected event_type 'device_state', got %q", sub.EventType)
	}

	// List
	subs := sm.list()
	if len(subs) != 1 {
		t.Fatalf("expected 1 subscription, got %d", len(subs))
	}

	// Remove
	if !sm.remove(sub.ID) {
		t.Error("remove should return true")
	}
	if sm.remove(sub.ID) {
		t.Error("second remove should return false")
	}

	subs = sm.list()
	if len(subs) != 0 {
		t.Errorf("expected 0 subscriptions after remove, got %d", len(subs))
	}
}

func TestSubscriptionManager_RemoveNonexistent(t *testing.T) {
	sm := newSubscriptionManager()
	if sm.remove("sub-9999") {
		t.Error("should return false for nonexistent ID")
	}
}

// --- matchesSubscription ---

func TestMatchesSubscription_Wildcard(t *testing.T) {
	sub := &EventSubscription{EventType: "*"}
	evt := Event{Type: "device_state", DeviceID: 8}
	if !matchesSubscription(sub, evt) {
		t.Error("wildcard should match any event")
	}
}

func TestMatchesSubscription_ExactType(t *testing.T) {
	sub := &EventSubscription{EventType: "device_state"}
	if !matchesSubscription(sub, Event{Type: "device_state"}) {
		t.Error("exact type should match")
	}
	if matchesSubscription(sub, Event{Type: "device_added"}) {
		t.Error("different type should not match")
	}
}

func TestMatchesSubscription_FilterNodeID(t *testing.T) {
	sub := &EventSubscription{
		EventType: "device_state",
		Filter:    map[string]string{"node_id": "8"},
	}
	if !matchesSubscription(sub, Event{Type: "device_state", DeviceID: 8}) {
		t.Error("matching node_id filter should match")
	}
	if matchesSubscription(sub, Event{Type: "device_state", DeviceID: 1}) {
		t.Error("non-matching node_id filter should not match")
	}
}

func TestMatchesSubscription_FilterKey(t *testing.T) {
	sub := &EventSubscription{
		EventType: "device_state",
		Filter:    map[string]string{"key": "on"},
	}
	if !matchesSubscription(sub, Event{Type: "device_state", Key: "on"}) {
		t.Error("matching key filter should match")
	}
	if matchesSubscription(sub, Event{Type: "device_state", Key: "contact"}) {
		t.Error("non-matching key filter should not match")
	}
}

// --- webhook dispatch integration test ---

func TestWebhookDispatch_Integration(t *testing.T) {
	var received int32
	var receivedEvt Event

	// Callback server
	callbackSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&received, 1)
		json.NewDecoder(r.Body).Decode(&receivedEvt)
		w.WriteHeader(http.StatusOK)
	}))
	defer callbackSrv.Close()

	sm := newSubscriptionManager()
	sm.add("device_state", callbackSrv.URL, nil)

	// Dispatch matching event
	sm.matchAndDispatch(Event{Type: "device_state", DeviceID: 8, Key: "on", Value: true})

	// Wait for async webhook
	time.Sleep(200 * time.Millisecond)

	if atomic.LoadInt32(&received) != 1 {
		t.Fatalf("expected 1 webhook call, got %d", atomic.LoadInt32(&received))
	}
	if receivedEvt.Type != "device_state" {
		t.Errorf("expected type 'device_state', got %q", receivedEvt.Type)
	}
	if receivedEvt.DeviceID != 8 {
		t.Errorf("expected device_id 8, got %d", receivedEvt.DeviceID)
	}
}

func TestWebhookDispatch_NoMatchSkipped(t *testing.T) {
	var received int32

	callbackSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&received, 1)
		w.WriteHeader(http.StatusOK)
	}))
	defer callbackSrv.Close()

	sm := newSubscriptionManager()
	sm.add("device_added", callbackSrv.URL, nil) // only device_added

	// Dispatch non-matching event
	sm.matchAndDispatch(Event{Type: "device_state", DeviceID: 8})

	time.Sleep(100 * time.Millisecond)

	if atomic.LoadInt32(&received) != 0 {
		t.Errorf("expected 0 webhook calls for non-matching event, got %d", atomic.LoadInt32(&received))
	}
}

func TestWebhookDispatch_MultipleSubscribers(t *testing.T) {
	var received int32

	callbackSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&received, 1)
		w.WriteHeader(http.StatusOK)
	}))
	defer callbackSrv.Close()

	sm := newSubscriptionManager()
	sm.add("*", callbackSrv.URL, nil)
	sm.add("device_state", callbackSrv.URL, nil)

	sm.matchAndDispatch(Event{Type: "device_state", DeviceID: 8})

	time.Sleep(200 * time.Millisecond)

	if atomic.LoadInt32(&received) != 2 {
		t.Errorf("expected 2 webhook calls, got %d", atomic.LoadInt32(&received))
	}
}

// --- HTTP endpoint tests ---

func TestAPISubscribe_RegisterAndList(t *testing.T) {
	h := testHub(t)
	h.subscriptions = newSubscriptionManager()
	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	// POST /api/subscribe
	body := `{"event_type":"device_state","callback":"http://example.com/hook"}`
	resp, err := http.Post(srv.URL+"/api/subscribe", "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("expected 201, got %d", resp.StatusCode)
	}

	var sub EventSubscription
	json.NewDecoder(resp.Body).Decode(&sub)
	if sub.ID == "" {
		t.Error("expected non-empty ID")
	}
	if sub.EventType != "device_state" {
		t.Errorf("expected event_type 'device_state', got %q", sub.EventType)
	}

	// GET /api/subscriptions
	resp2, err := http.Get(srv.URL + "/api/subscriptions")
	if err != nil {
		t.Fatal(err)
	}
	defer resp2.Body.Close()

	var subs []*EventSubscription
	json.NewDecoder(resp2.Body).Decode(&subs)
	if len(subs) != 1 {
		t.Fatalf("expected 1 subscription, got %d", len(subs))
	}
}

func TestAPISubscribe_MissingFields(t *testing.T) {
	h := testHub(t)
	h.subscriptions = newSubscriptionManager()
	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	// Missing callback
	body := `{"event_type":"device_state"}`
	resp, _ := http.Post(srv.URL+"/api/subscribe", "application/json", strings.NewReader(body))
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", resp.StatusCode)
	}
}

func TestAPIUnsubscribe(t *testing.T) {
	h := testHub(t)
	h.subscriptions = newSubscriptionManager()
	sub := h.subscriptions.add("*", "http://example.com/hook", nil)

	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	// DELETE /api/subscribe/{id}
	req, _ := http.NewRequest(http.MethodDelete, srv.URL+"/api/subscribe/"+sub.ID, nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}

	// Second delete should 404
	req2, _ := http.NewRequest(http.MethodDelete, srv.URL+"/api/subscribe/"+sub.ID, nil)
	resp2, _ := http.DefaultClient.Do(req2)
	defer resp2.Body.Close()

	if resp2.StatusCode != http.StatusNotFound {
		t.Errorf("expected 404, got %d", resp2.StatusCode)
	}
}

func TestAPISubscribe_MethodNotAllowed(t *testing.T) {
	h := testHub(t)
	h.subscriptions = newSubscriptionManager()
	mux := testMux(h)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	resp, _ := http.Get(srv.URL + "/api/subscribe")
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusMethodNotAllowed {
		t.Errorf("expected 405, got %d", resp.StatusCode)
	}
}

// --- End-to-end: event → webhook delivery ---

func TestE2E_EventTriggersWebhook(t *testing.T) {
	var received int32
	callbackSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&received, 1)
		w.WriteHeader(http.StatusOK)
	}))
	defer callbackSrv.Close()

	h := testHub(t)
	h.subscriptions = newSubscriptionManager()
	h.subscriptions.add("device_state", callbackSrv.URL, nil)

	// Start broadcaster
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go h.eventBroadcaster(ctx)

	// Inject event
	h.eventCh <- Event{Type: "device_state", DeviceID: 8, Key: "on", Value: true}

	time.Sleep(300 * time.Millisecond)

	if atomic.LoadInt32(&received) != 1 {
		t.Errorf("expected 1 webhook delivery, got %d", atomic.LoadInt32(&received))
	}
}
