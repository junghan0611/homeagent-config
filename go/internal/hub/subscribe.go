package hub

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"
)

// EventSubscription represents a webhook subscription for hub events.
type EventSubscription struct {
	ID        string            `json:"id"`
	EventType string            `json:"event_type"` // "device_change", "device_state", "device_added", "*"
	Callback  string            `json:"callback"`   // webhook URL
	Filter    map[string]string `json:"filter,omitempty"`
	CreatedAt time.Time         `json:"created_at"`
}

// subscriptionManager manages webhook subscriptions.
type subscriptionManager struct {
	mu   sync.RWMutex
	subs map[string]*EventSubscription
	seq  int // simple monotonic counter for IDs
}

func newSubscriptionManager() *subscriptionManager {
	return &subscriptionManager{
		subs: make(map[string]*EventSubscription),
	}
}

func (sm *subscriptionManager) add(eventType, callback string, filter map[string]string) *EventSubscription {
	sm.mu.Lock()
	defer sm.mu.Unlock()

	sm.seq++
	sub := &EventSubscription{
		ID:        fmt.Sprintf("sub-%04d", sm.seq),
		EventType: eventType,
		Callback:  callback,
		Filter:    filter,
		CreatedAt: time.Now(),
	}
	sm.subs[sub.ID] = sub
	return sub
}

func (sm *subscriptionManager) remove(id string) bool {
	sm.mu.Lock()
	defer sm.mu.Unlock()

	if _, ok := sm.subs[id]; !ok {
		return false
	}
	delete(sm.subs, id)
	return true
}

func (sm *subscriptionManager) list() []*EventSubscription {
	sm.mu.RLock()
	defer sm.mu.RUnlock()

	result := make([]*EventSubscription, 0, len(sm.subs))
	for _, s := range sm.subs {
		result = append(result, s)
	}
	return result
}

// matchAndDispatch sends the event to all matching subscriptions via outbound webhook.
func (sm *subscriptionManager) matchAndDispatch(evt Event) {
	sm.mu.RLock()
	var matched []*EventSubscription
	for _, sub := range sm.subs {
		if matchesSubscription(sub, evt) {
			matched = append(matched, sub)
		}
	}
	sm.mu.RUnlock()

	for _, sub := range matched {
		go sendWebhook(sub.Callback, evt)
	}
}

// matchesSubscription checks if an event matches a subscription's type and filters.
func matchesSubscription(sub *EventSubscription, evt Event) bool {
	// Wildcard matches everything
	if sub.EventType != "*" && sub.EventType != evt.Type {
		return false
	}

	// Apply filters
	for k, v := range sub.Filter {
		switch k {
		case "node_id":
			if fmt.Sprintf("%d", evt.DeviceID) != v {
				return false
			}
		case "key":
			if evt.Key != v {
				return false
			}
		}
	}
	return true
}

// sendWebhook POSTs the event to the callback URL with a 5s timeout.
func sendWebhook(callback string, evt Event) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	body, err := json.Marshal(evt)
	if err != nil {
		log.Printf("[webhook] marshal error: %v", err)
		return
	}

	req, err := http.NewRequestWithContext(ctx, "POST", callback, bytes.NewReader(body))
	if err != nil {
		log.Printf("[webhook] request error: %v", err)
		return
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "HomeAgent-Webhook/1.0")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		log.Printf("[webhook] send to %s failed: %v", callback, err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		log.Printf("[webhook] %s returned %d", callback, resp.StatusCode)
	}
}

// handleSubscribe handles POST /api/subscribe (register) and GET /api/subscriptions (list).
func (h *Hub) handleSubscribe(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPost:
		var req struct {
			EventType string            `json:"event_type"`
			Callback  string            `json:"callback"`
			Filter    map[string]string `json:"filter,omitempty"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, `{"error":"잘못된 JSON 형식"}`, http.StatusBadRequest)
			return
		}
		if req.EventType == "" || req.Callback == "" {
			http.Error(w, `{"error":"event_type과 callback 필수"}`, http.StatusBadRequest)
			return
		}

		sub := h.subscriptions.add(req.EventType, req.Callback, req.Filter)
		log.Printf("[subscribe] registered: %s → %s (%s)", sub.ID, sub.Callback, sub.EventType)

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(sub)

	default:
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
	}
}

// handleSubscriptions handles GET /api/subscriptions (list all).
func (h *Hub) handleSubscriptions(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET only", http.StatusMethodNotAllowed)
		return
	}

	subs := h.subscriptions.list()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(subs)
}

// handleUnsubscribe handles DELETE /api/subscribe/{id}.
func (h *Hub) handleUnsubscribe(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		http.Error(w, "DELETE only", http.StatusMethodNotAllowed)
		return
	}

	// Extract ID from path: /api/subscribe/sub-0001
	id := strings.TrimPrefix(r.URL.Path, "/api/subscribe/")
	if id == "" {
		http.Error(w, `{"error":"subscription ID 필수"}`, http.StatusBadRequest)
		return
	}

	if !h.subscriptions.remove(id) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "구독을 찾을 수 없습니다"})
		return
	}

	log.Printf("[subscribe] removed: %s", id)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}
