// Package a2a implements A2A protocol support for HomeAgent.
//
// HomeAgent exposes its device control, status query, and space summary
// capabilities as A2A skills. External agents can discover HomeAgent via
// /.well-known/agent.json and interact through JSON-RPC at /a2a.
package a2a

import (
	"context"
	"encoding/json"
	"fmt"
	"iter"
	"strings"

	"github.com/a2aproject/a2a-go/v2/a2a"
	"github.com/a2aproject/a2a-go/v2/a2asrv"
)

// DeviceLister provides device listing capability from hub.
type DeviceLister interface {
	ListDevicesJSON() (json.RawMessage, error)
}

// ChatHandler provides natural language processing from hub.
type ChatHandler interface {
	Chat(ctx context.Context, message string) (string, error)
}

// HomeAgentExecutor implements a2asrv.AgentExecutor.
// It translates A2A messages into HomeAgent actions.
type HomeAgentExecutor struct {
	Devices DeviceLister
	Chat    ChatHandler
}

var _ a2asrv.AgentExecutor = (*HomeAgentExecutor)(nil)

// Execute processes an incoming A2A message and yields response events.
func (e *HomeAgentExecutor) Execute(ctx context.Context, execCtx *a2asrv.ExecutorContext) iter.Seq2[a2a.Event, error] {
	return func(yield func(a2a.Event, error) bool) {
		// Extract text from message parts
		text := extractText(execCtx.Message)
		if text == "" {
			msg := a2a.NewMessage(a2a.MessageRoleAgent, a2a.NewTextPart("메시지에 텍스트가 없습니다."))
			yield(msg, nil)
			return
		}

		// Route to appropriate skill based on intent
		response := e.handleMessage(ctx, text)

		msg := a2a.NewMessage(a2a.MessageRoleAgent, a2a.NewTextPart(response))
		yield(msg, nil)
	}
}

// Cancel handles task cancellation.
func (e *HomeAgentExecutor) Cancel(ctx context.Context, execCtx *a2asrv.ExecutorContext) iter.Seq2[a2a.Event, error] {
	return func(yield func(a2a.Event, error) bool) {
		event := a2a.NewStatusUpdateEvent(execCtx, a2a.TaskStateCanceled, nil)
		yield(event, nil)
	}
}

// handleMessage routes the text message to the appropriate handler.
func (e *HomeAgentExecutor) handleMessage(ctx context.Context, text string) string {
	lower := strings.ToLower(text)

	// Skill routing — keyword based for Phase 0
	switch {
	case containsAny(lower, "device", "디바이스", "장치", "목록", "list"):
		return e.handleDeviceList()
	case containsAny(lower, "status", "상태", "state"):
		return e.handleDeviceList()
	default:
		// Fall through to chat/LLM if available
		if e.Chat != nil {
			resp, err := e.Chat.Chat(ctx, text)
			if err != nil {
				return fmt.Sprintf("처리 중 오류: %v", err)
			}
			return resp
		}
		return fmt.Sprintf("HomeAgent가 메시지를 수신했습니다: %q\n현재 지원 스킬: device_list, device_status, natural_language", text)
	}
}

// handleDeviceList returns device list as formatted text.
func (e *HomeAgentExecutor) handleDeviceList() string {
	if e.Devices == nil {
		return "디바이스 정보를 사용할 수 없습니다. (matterjs-server 미연결)"
	}
	data, err := e.Devices.ListDevicesJSON()
	if err != nil {
		return fmt.Sprintf("디바이스 조회 실패: %v", err)
	}
	return string(data)
}

// extractText concatenates all text parts from a message.
func extractText(msg *a2a.Message) string {
	if msg == nil {
		return ""
	}
	var texts []string
	for _, part := range msg.Parts {
		if t := part.Text(); t != "" {
			texts = append(texts, t)
		}
	}
	return strings.Join(texts, " ")
}

// containsAny checks if s contains any of the keywords.
func containsAny(s string, keywords ...string) bool {
	for _, kw := range keywords {
		if strings.Contains(s, kw) {
			return true
		}
	}
	return false
}
