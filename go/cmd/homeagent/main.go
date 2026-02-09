package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/junghan0611/homeagent/internal/config"
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

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"status":"ok","version":"%s"}`, version)
	})

	srv := &http.Server{Addr: cfg.HTTPAddr, Handler: mux}

	// graceful shutdown
	go func() {
		sig := make(chan os.Signal, 1)
		signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
		<-sig
		log.Println("종료 중...")
		srv.Close()
	}()

	log.Printf("HTTP 서버 시작: %s", cfg.HTTPAddr)
	if err := srv.ListenAndServe(); err != http.ErrServerClosed {
		log.Fatalf("HTTP 서버 오류: %v", err)
	}
}
