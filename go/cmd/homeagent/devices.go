package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"

	"github.com/spf13/cobra"
)

func devicesCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "devices",
		Short: "디바이스 목록 (CLI/robot mode)",
		Long:  "REST API에서 디바이스 목록을 가져와 JSON으로 출력. 에이전트 연동용.",
		RunE:  runDevices,
	}
	cmd.Flags().String("server", "http://localhost:8080", "HomeAgent 서버 주소")
	cmd.Flags().Bool("json", false, "JSON 출력 (기본: 테이블)")
	return cmd
}

func controlCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "control [node_id] [command]",
		Short: "디바이스 제어 (CLI)",
		Long:  "디바이스에 명령 전송. 예: homeagent control 8 on",
		Args:  cobra.ExactArgs(2),
		RunE:  runControl,
	}
	cmd.Flags().String("server", "http://localhost:8080", "HomeAgent 서버 주소")
	cmd.Flags().Int("level", 0, "밝기 레벨 (set_level 시 0-254)")
	return cmd
}

func runDevices(cmd *cobra.Command, args []string) error {
	serverURL, _ := cmd.Flags().GetString("server")
	jsonMode, _ := cmd.Flags().GetBool("json")

	resp, err := http.Get(serverURL + "/api/devices")
	if err != nil {
		return fmt.Errorf("서버 연결 실패: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)

	if jsonMode {
		// robot mode: JSON 그대로 stdout
		fmt.Println(string(body))
		return nil
	}

	// 테이블 모드
	var devices []map[string]interface{}
	if err := json.Unmarshal(body, &devices); err != nil {
		return fmt.Errorf("JSON 파싱 실패: %w", err)
	}

	fmt.Printf("%-6s %-16s %-10s %-16s %-8s %s\n",
		"Node", "Name", "Room", "Type", "Avail", "State")
	fmt.Println("------ ---------------- ---------- ---------------- -------- -----")

	for _, d := range devices {
		nodeID := d["node_id"]
		name := d["name"]
		room := d["room"]
		devType := d["type"]
		avail := d["available"]
		state := d["state"]

		stateJSON, _ := json.Marshal(state)
		icon := "●"
		if avail != true {
			icon = "○"
		}

		fmt.Printf("%-6v %s %-14v %-10v %-16v %-8v %s\n",
			nodeID, icon, name, room, devType, avail, string(stateJSON))
	}

	return nil
}

func runControl(cmd *cobra.Command, args []string) error {
	serverURL, _ := cmd.Flags().GetString("server")

	var nodeID int
	fmt.Sscanf(args[0], "%d", &nodeID)
	command := args[1]

	payload := map[string]interface{}{
		"node_id": nodeID,
		"command": command,
	}

	// level 옵션
	level, _ := cmd.Flags().GetInt("level")
	if command == "set_level" && level > 0 {
		payload["level"] = level
	}

	body, _ := json.Marshal(payload)

	resp, err := http.Post(serverURL+"/api/devices/command", "application/json",
		bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("서버 연결 실패: %w", err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		fmt.Fprintf(os.Stderr, "오류: %s\n", string(respBody))
		os.Exit(1)
	}

	fmt.Println(string(respBody))
	return nil
}
