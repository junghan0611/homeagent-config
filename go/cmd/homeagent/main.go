package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var version = "dev"

func main() {
	rootCmd := &cobra.Command{
		Use:   "homeagent",
		Short: "HomeAgent — 오프라인 스마트홈 에이전트",
		Long:  "Matter 디바이스를 제어하는 오프라인 에이전트. REST API, TUI, CLI 지원.",
		// 인자 없이 실행하면 serve (하위 호환)
		RunE: func(cmd *cobra.Command, args []string) error {
			return runServe(cmd, args)
		},
	}

	rootCmd.AddCommand(serveCmd())
	rootCmd.AddCommand(tuiCmd())
	rootCmd.AddCommand(devicesCmd())
	rootCmd.AddCommand(controlCmd())
	rootCmd.AddCommand(versionCmd())

	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func versionCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "버전 출력",
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Println(version)
		},
	}
}
