package a2a

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/a2aproject/a2a-go/v2/a2a"
	"github.com/a2aproject/a2a-go/v2/a2asrv"
)

// mockDeviceLister returns a fixed device list.
type mockDeviceLister struct{}

func (m *mockDeviceLister) ListDevicesJSON() (json.RawMessage, error) {
	return json.RawMessage(`[{"node_id":8,"name":"거실 플러그","type":"on_off_plug","state":{"on":true}}]`), nil
}

// mockChatHandler returns a fixed chat response.
type mockChatHandler struct{}

func (m *mockChatHandler) Chat(ctx context.Context, message string) (string, error) {
	return "LLM 응답: " + message, nil
}

func newTestExecutor() *HomeAgentExecutor {
	return &HomeAgentExecutor{
		Devices: &mockDeviceLister{},
		Chat:    &mockChatHandler{},
	}
}

func newExecCtx(text string) *a2asrv.ExecutorContext {
	msg := a2a.NewMessage(a2a.MessageRoleUser, a2a.NewTextPart(text))
	msg.ID = "test-msg-1"
	return &a2asrv.ExecutorContext{
		Message:   msg,
		TaskID:    "test-task-1",
		ContextID: "test-ctx-1",
	}
}

func TestExecute_TaskLifecycle(t *testing.T) {
	exec := newTestExecutor()
	ctx := context.Background()
	execCtx := newExecCtx("디바이스 목록")

	var events []a2a.Event
	for event, err := range exec.Execute(ctx, execCtx) {
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		events = append(events, event)
	}

	// Phase 1: submitted → working → artifact → completed = 4 events
	if len(events) != 4 {
		t.Fatalf("expected 4 events, got %d", len(events))
	}

	// Event 0: Task (submitted)
	task, ok := events[0].(*a2a.Task)
	if !ok {
		t.Fatalf("event 0: expected *a2a.Task, got %T", events[0])
	}
	if task.Status.State != a2a.TaskStateSubmitted {
		t.Errorf("event 0: expected submitted, got %s", task.Status.State)
	}

	// Event 1: StatusUpdate (working)
	status1, ok := events[1].(*a2a.TaskStatusUpdateEvent)
	if !ok {
		t.Fatalf("event 1: expected *a2a.TaskStatusUpdateEvent, got %T", events[1])
	}
	if status1.Status.State != a2a.TaskStateWorking {
		t.Errorf("event 1: expected working, got %s", status1.Status.State)
	}

	// Event 2: ArtifactUpdate (device list)
	artifact, ok := events[2].(*a2a.TaskArtifactUpdateEvent)
	if !ok {
		t.Fatalf("event 2: expected *a2a.TaskArtifactUpdateEvent, got %T", events[2])
	}
	if len(artifact.Artifact.Parts) == 0 {
		t.Fatal("event 2: artifact has no parts")
	}
	text := artifact.Artifact.Parts[0].Text()
	if text == "" {
		t.Error("event 2: artifact text is empty")
	}
	// Should contain device data
	if !containsAny(text, "거실 플러그", "on_off_plug") {
		t.Errorf("event 2: expected device data, got %q", text)
	}

	// Event 3: StatusUpdate (completed)
	status3, ok := events[3].(*a2a.TaskStatusUpdateEvent)
	if !ok {
		t.Fatalf("event 3: expected *a2a.TaskStatusUpdateEvent, got %T", events[3])
	}
	if status3.Status.State != a2a.TaskStateCompleted {
		t.Errorf("event 3: expected completed, got %s", status3.Status.State)
	}
}

func TestExecute_EmptyMessage(t *testing.T) {
	exec := newTestExecutor()
	ctx := context.Background()

	msg := a2a.NewMessage(a2a.MessageRoleUser) // no parts
	msg.ID = "test-msg-empty"
	execCtx := &a2asrv.ExecutorContext{
		Message:   msg,
		TaskID:    "test-task-empty",
		ContextID: "test-ctx-empty",
	}

	var events []a2a.Event
	for event, err := range exec.Execute(ctx, execCtx) {
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		events = append(events, event)
	}

	// Should fail immediately with a status update
	if len(events) != 1 {
		t.Fatalf("expected 1 event (failed), got %d", len(events))
	}

	status, ok := events[0].(*a2a.TaskStatusUpdateEvent)
	if !ok {
		t.Fatalf("expected *a2a.TaskStatusUpdateEvent, got %T", events[0])
	}
	if status.Status.State != a2a.TaskStateFailed {
		t.Errorf("expected failed, got %s", status.Status.State)
	}
}

func TestExecute_ExistingTask(t *testing.T) {
	exec := newTestExecutor()
	ctx := context.Background()

	// Simulate existing task (multi-turn)
	execCtx := newExecCtx("상태")
	execCtx.StoredTask = &a2a.Task{
		ID:        "test-task-existing",
		ContextID: "test-ctx-existing",
		Status:    a2a.TaskStatus{State: a2a.TaskStateWorking},
	}

	var events []a2a.Event
	for event, err := range exec.Execute(ctx, execCtx) {
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		events = append(events, event)
	}

	// Existing task: no submitted event → working + artifact + completed = 3 events
	if len(events) != 3 {
		t.Fatalf("expected 3 events (no submitted), got %d", len(events))
	}

	// First event should be working (not submitted)
	status, ok := events[0].(*a2a.TaskStatusUpdateEvent)
	if !ok {
		t.Fatalf("event 0: expected *a2a.TaskStatusUpdateEvent, got %T", events[0])
	}
	if status.Status.State != a2a.TaskStateWorking {
		t.Errorf("event 0: expected working, got %s", status.Status.State)
	}
}

func TestExecute_ChatFallback(t *testing.T) {
	exec := newTestExecutor()
	ctx := context.Background()
	execCtx := newExecCtx("안녕하세요, 오늘 날씨가 좋네요")

	var events []a2a.Event
	for event, err := range exec.Execute(ctx, execCtx) {
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		events = append(events, event)
	}

	if len(events) != 4 {
		t.Fatalf("expected 4 events, got %d", len(events))
	}

	artifact, ok := events[2].(*a2a.TaskArtifactUpdateEvent)
	if !ok {
		t.Fatalf("event 2: expected artifact, got %T", events[2])
	}
	text := artifact.Artifact.Parts[0].Text()
	if !containsAny(text, "LLM 응답") {
		t.Errorf("expected chat fallback, got %q", text)
	}
}

func TestCancel(t *testing.T) {
	exec := newTestExecutor()
	ctx := context.Background()
	execCtx := &a2asrv.ExecutorContext{
		TaskID:    "test-task-cancel",
		ContextID: "test-ctx-cancel",
	}

	var events []a2a.Event
	for event, err := range exec.Cancel(ctx, execCtx) {
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		events = append(events, event)
	}

	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}

	status, ok := events[0].(*a2a.TaskStatusUpdateEvent)
	if !ok {
		t.Fatalf("expected *a2a.TaskStatusUpdateEvent, got %T", events[0])
	}
	if status.Status.State != a2a.TaskStateCanceled {
		t.Errorf("expected canceled, got %s", status.Status.State)
	}
}

func TestNewAgentCard(t *testing.T) {
	card := NewAgentCard("http://localhost:8080")

	if card.Name != "HomeAgent" {
		t.Errorf("expected name HomeAgent, got %s", card.Name)
	}
	if !card.Capabilities.Streaming {
		t.Error("expected streaming to be enabled (Phase 1)")
	}
	if len(card.Skills) != 6 {
		t.Errorf("expected 6 skills, got %d", len(card.Skills))
	}
	if len(card.SupportedInterfaces) != 1 {
		t.Errorf("expected 1 interface, got %d", len(card.SupportedInterfaces))
	}
}
