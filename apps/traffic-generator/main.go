package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

var (
	merchants = []string{"merch-somtum-der", "merch-jay-fai", "merch-thip-samai", "merch-after-you", "merch-mk-restaurant"}
	dishes    = []string{"Pad Thai Special", "Tom Yum Goong", "Green Curry Chicken", "Mango Sticky Rice", "Som Tum Thai"}
)

func main() {
	targetURL := flag.String("target-url", "", "Kong Gateway Base URL (e.g. http://kong-proxy.ingress.svc.cluster.local:80)")
	rpm := flag.Int("rpm", 60, "Requests per minute")
	chaosRate := flag.Float64("chaos-rate", 0.05, "Chaos injection rate (e.g. 0.05 for 5% poisoned pills)")
	flag.Parse()

	if *targetURL == "" {
		*targetURL = os.Getenv("KONG_GATEWAY_URL")
		if *targetURL == "" {
			*targetURL = "http://kong-proxy.ingress.svc.cluster.local:80"
		}
	}

	log.Printf("[TRAFFIC_GENERATOR] Starting load generator. Target: %s, Rate: %d RPM, Chaos: %.1f%%",
		*targetURL, *rpm, *chaosRate*100)

	interval := time.Minute / time.Duration(*rpm)
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	client := &http.Client{Timeout: 5 * time.Second}
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	orderSeq := 1000

	for {
		select {
		case <-sigChan:
			log.Println("[TRAFFIC_GENERATOR] Stopping traffic generator...")
			return
		case <-ticker.C:
			orderSeq++
			isChaos := rand.Float64() < *chaosRate

			var amount float64 = float64(rand.Intn(500) + 50)
			if isChaos {
				// Chaos injection: negative amount violates Draft-07 schema contract
				amount = -999.00
				log.Printf("[CHAOS_INJECTOR] Injecting schema violation: order_id=ord-%d, amount=%.2f", orderSeq, amount)
			}

			orderPayload := map[string]interface{}{
				"order_id":         fmt.Sprintf("ord-%d", orderSeq),
				"customer_id":      fmt.Sprintf("cust-%d", rand.Intn(100)+1),
				"merchant_id":      merchants[rand.Intn(len(merchants))],
				"amount":           amount,
				"currency":         "THB",
				"delivery_address": "Sukhumvit Soi 55, Thonglor, Bangkok",
				"items": []map[string]interface{}{
					{
						"item_id":  fmt.Sprintf("item-%d", rand.Intn(20)+1),
						"name":     dishes[rand.Intn(len(dishes))],
						"price":    amount,
						"quantity": 1,
					},
				},
			}

			payloadBytes, _ := json.Marshal(orderPayload)
			resp, err := client.Post(*targetURL+"/v1/orders", "application/json", bytes.NewBuffer(payloadBytes))
			if err != nil {
				log.Printf("[CLIENT_ERROR] Failed to send order: %v", err)
				continue
			}
			_ = resp.Body.Close()

			if resp.StatusCode >= 200 && resp.StatusCode < 300 {
				log.Printf("[CLIENT_SUCCESS] Order placed: ord-%d (HTTP %d)", orderSeq, resp.StatusCode)
			} else {
				log.Printf("[CLIENT_REJECTED] Order rejected by policy: ord-%d (HTTP %d)", orderSeq, resp.StatusCode)
			}
		}
	}
}
