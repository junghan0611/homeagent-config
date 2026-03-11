package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"

	"github.com/spf13/cobra"
)

func a2aTestCmd() *cobra.Command {
	var server string
	var message string

	cmd := &cobra.Command{
		Use:   "a2a-test",
		Short: "A2A 프로토콜 테스트 클라이언트",
		Long:  "HomeAgent A2A 서버에 JSON-RPC message/send 요청을 보내고 응답을 출력.",
		RunE: func(cmd *cobra.Command, args []string) error {
			return runA2ATest(server, message)
		},
	}

	cmd.Flags().StringVar(&server, "server", "http://localhost:8080/a2a", "A2A 서버 URL")
	cmd.Flags().StringVarP(&message, "message", "m", "", "보낼 메시지 (필수)")
	cmd.MarkFlagRequired("message")

	return cmd
}

func a2aCardCmd() *cobra.Command {
	var server string

	cmd := &cobra.Command{
		Use:   "a2a-card",
		Short: "A2A AgentCard 조회",
		Long:  "HomeAgent의 /.well-known/agent.json을 가져와 출력.",
		RunE: func(cmd *cobra.Command, args []string) error {
			return runA2ACard(server)
		},
	}

	cmd.Flags().StringVar(&server, "server", "http://localhost:8080", "서버 base URL")

	return cmd
}

func runA2ATest(serverURL, message string) error {
	// JSON-RPC request (A2A v1.0: PascalCase method names)
	reqBody := fmt.Sprintf(`{
		"jsonrpc": "2.0",
		"method": "SendMessage",
		"id": "test-1",
		"params": {
			"message": {
				"role": "ROLE_USER",
				"parts": [{"text": %q}],
				"messageId": "msg-1"
			}
		}
	}`, message)

	resp, err := http.Post(serverURL, "application/json", strings.NewReader(reqBody))
	if err != nil {
		return fmt.Errorf("요청 실패: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("응답 읽기 실패: %w", err)
	}

	// Pretty print
	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		// Not JSON, print raw
		fmt.Println(string(body))
		return nil
	}

	pretty, _ := json.MarshalIndent(result, "", "  ")
	fmt.Println(string(pretty))

	return nil
}

func runA2ACard(baseURL string) error {
	url := baseURL + "/.well-known/agent.json"
	resp, err := http.Get(url)
	if err != nil {
		return fmt.Errorf("요청 실패: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("읽기 실패: %w", err)
	}

	var card map[string]interface{}
	if err := json.Unmarshal(body, &card); err != nil {
		log.Printf("JSON 파싱 실패, raw 출력:")
		fmt.Println(string(body))
		return nil
	}

	pretty, _ := json.MarshalIndent(card, "", "  ")
	fmt.Println(string(pretty))
	return nil
}
