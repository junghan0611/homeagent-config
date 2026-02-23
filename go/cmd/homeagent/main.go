package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/junghan0611/homeagent/internal/config"
	"github.com/junghan0611/homeagent/internal/hub"
)

var version = "dev"

func main() {
	showVersion := flag.Bool("version", false, "버전 출력")
	flag.Parse()

	if *showVersion {
		fmt.Println(version)
		os.Exit(0)
	}

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

	// Run hub (blocking — listens for Matter events)
	if err := h.Run(ctx); err != nil {
		if ctx.Err() != nil {
			log.Println("homeagent 종료")
		} else {
			log.Fatalf("hub 오류: %v", err)
		}
	}
}
