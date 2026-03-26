// mdns-poc — Android에서 Go 네이티브 mDNS browse PoC
// _matterc._udp (commissionable Matter 디바이스) 검색
// _matter._tcp (operational Matter 디바이스) 검색
//
// 빌드: GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o mdns-poc ./cmd/mdns-poc/
// 실행: adb push mdns-poc /data/local/tmp/ && adb shell /data/local/tmp/mdns-poc
package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/grandcat/zeroconf"
)

func main() {
	log.Println("=== Go mDNS PoC — Android UDP multicast 테스트 ===")

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	// 1. _matterc._udp — commissionable (페어링 대기 중인 디바이스)
	log.Println("Browsing _matterc._udp (commissionable)...")
	go browse(ctx, "_matterc._udp", "local.")

	// 2. _matter._tcp — operational (이미 커미셔닝된 디바이스)
	log.Println("Browsing _matter._tcp (operational)...")
	go browse(ctx, "_matter._tcp", "local.")

	<-ctx.Done()
	log.Println("=== 15초 경과 — 종료 ===")
}

func browse(ctx context.Context, service, domain string) {
	resolver, err := zeroconf.NewResolver(nil)
	if err != nil {
		log.Printf("[%s] resolver 생성 실패: %v", service, err)
		return
	}

	entries := make(chan *zeroconf.ServiceEntry)
	go func() {
		for entry := range entries {
			fmt.Printf("\n🔍 [%s] 디바이스 발견!\n", service)
			fmt.Printf("   Name:   %s\n", entry.ServiceInstanceName())
			fmt.Printf("   Host:   %s\n", entry.HostName)
			fmt.Printf("   Port:   %d\n", entry.Port)
			if len(entry.AddrIPv4) > 0 {
				fmt.Printf("   IPv4:   %v\n", entry.AddrIPv4)
			}
			if len(entry.AddrIPv6) > 0 {
				fmt.Printf("   IPv6:   %v\n", entry.AddrIPv6)
			}
			if len(entry.Text) > 0 {
				fmt.Printf("   TXT:    %v\n", entry.Text)
			}
		}
	}()

	if err := resolver.Browse(ctx, service, domain, entries); err != nil {
		log.Printf("[%s] browse 실패: %v", service, err)
	}
}
