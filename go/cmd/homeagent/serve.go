package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	"github.com/a2aproject/a2a-go/v2/a2asrv"
	homeagentA2A "github.com/junghan0611/homeagent/internal/a2a"
	"github.com/junghan0611/homeagent/internal/config"
	"github.com/junghan0611/homeagent/internal/hub"
	"github.com/spf13/cobra"
)

func serveCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "serve",
		Short: "HTTP 서버 시작 (기본 동작)",
		Long:  "Go 백엔드 + REST API + Matter WS 연결. 브라우저/Flutter/TUI에서 접속.",
		RunE:  runServe,
	}
}

func runServe(cmd *cobra.Command, args []string) error {
	cfg := config.Load()

	log.Printf("homeagent %s 시작", version)
	cfg.Print()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Graceful shutdown
	go func() {
		sig := make(chan os.Signal, 1)
		signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
		<-sig
		log.Println("종료 중...")
		cancel()
	}()

	// Hub (Matter + 상태머신)
	h := hub.New(cfg)

	// HTTP API
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"status":"ok","version":"%s"}`, version)
	})
	h.RegisterHTTP(mux)

	// A2A Protocol endpoint
	baseURL := fmt.Sprintf("http://localhost%s", cfg.HTTPAddr)
	agentCard := homeagentA2A.NewAgentCard(baseURL)

	adapter := &homeagentA2A.HubAdapter{
		DevicesFn: func() (json.RawMessage, error) {
			devices := h.Devices()
			return json.Marshal(devices)
		},
		// ChatFn: set to nil for Phase 0 (no LLM dependency)
	}
	executor := &homeagentA2A.HomeAgentExecutor{
		Devices: adapter,
		Chat:    adapter,
	}
	a2aHandler := a2asrv.NewHandler(executor)
	mux.Handle("/.well-known/agent.json", a2asrv.NewStaticAgentCardHandler(agentCard))
	mux.Handle("/a2a", a2asrv.NewJSONRPCHandler(a2aHandler))
	log.Printf("A2A 엔드포인트: %s/a2a", baseURL)

	// Static file serving (UI)
	uiDir := os.Getenv("HOMEAGENT_UI_DIR")
	if uiDir == "" {
		if exe, err := os.Executable(); err == nil {
			candidate := filepath.Join(filepath.Dir(exe), "ui")
			if info, err := os.Stat(candidate); err == nil && info.IsDir() {
				uiDir = candidate
			}
		}
	}
	if uiDir != "" {
		log.Printf("UI 서빙: %s", uiDir)
		fs := http.FileServer(http.Dir(uiDir))
		mux.Handle("/", fs)
	}

	srv := &http.Server{Addr: cfg.HTTPAddr, Handler: mux}
	go func() {
		log.Printf("HTTP 서버: %s", cfg.HTTPAddr)
		if err := srv.ListenAndServe(); err != http.ErrServerClosed {
			log.Fatalf("HTTP 서버 오류: %v", err)
		}
	}()
	go func() {
		<-ctx.Done()
		srv.Close()
	}()

	// Run hub (blocking)
	if err := h.Run(ctx); err != nil {
		if ctx.Err() != nil {
			log.Println("homeagent 종료")
			return nil
		}
		return fmt.Errorf("hub 오류: %w", err)
	}
	return nil
}
