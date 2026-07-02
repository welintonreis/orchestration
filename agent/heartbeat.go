package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

type pendingCommand struct {
	ID   int64  `json:"id"`
	Kind string `json:"kind"`
}

// runHeartbeatLoop never returns — it's the process's main blocking loop.
// Metrics + presence go out on every tick; any pending EdgeCommand rows come
// back and get ack'd immediately (there's no concrete command kind wired up
// yet — see docs/specs/feature-edge-compute.md — this just proves the
// offline-tolerant queue's round trip end to end so a real kind is a
// one-function addition later, not a new subsystem).
func runHeartbeatLoop(cfg Config, token string) {
	client := &http.Client{Timeout: 15 * time.Second}
	procPath := "/proc"

	for {
		m := collectMetrics(procPath)
		commands, err := heartbeat(client, cfg, token, m)
		if err != nil {
			log.Printf("[heartbeat] error: %v", err)
		} else {
			for _, cmd := range commands {
				log.Printf("[heartbeat] pending command #%d kind=%s (no handler — ack'd as-is)", cmd.ID, cmd.Kind)
				ackCommand(client, cfg, token, cmd.ID)
			}
		}
		time.Sleep(cfg.HeartbeatInterval)
	}
}

func heartbeat(client *http.Client, cfg Config, token string, m Metrics) ([]pendingCommand, error) {
	form := url.Values{
		"agent_version":         {AgentVersion},
		"os":                    {cfg.OS},
		"arch":                  {cfg.Arch},
		"metrics[cpu_percent]":  {fmt.Sprintf("%v", m.CPUPercent)},
		"metrics[ram_percent]":  {fmt.Sprintf("%v", m.RAMPercent)},
		"metrics[disk_percent]": {fmt.Sprintf("%v", m.DiskPercent)},
		"metrics[swap_percent]": {fmt.Sprintf("%v", m.SwapPercent)},
		"metrics[load_1m]":      {fmt.Sprintf("%v", m.Load1)},
		"metrics[load_5m]":      {fmt.Sprintf("%v", m.Load5)},
		"metrics[load_15m]":     {fmt.Sprintf("%v", m.Load15)},
	}

	req, err := http.NewRequest(http.MethodPost, strings.TrimRight(cfg.EdgeURL, "/")+"/api/edge/heartbeat", strings.NewReader(form.Encode()))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	var body struct {
		Commands []pendingCommand `json:"commands"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return nil, err
	}
	return body.Commands, nil
}

func ackCommand(client *http.Client, cfg Config, token string, id int64) {
	reqURL := strings.TrimRight(cfg.EdgeURL, "/") + "/api/edge/commands/" + strconv.FormatInt(id, 10) + "/ack"
	req, err := http.NewRequest(http.MethodPost, reqURL, strings.NewReader(url.Values{"result[ok]": {"true"}}.Encode()))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := client.Do(req)
	if err != nil {
		log.Printf("[heartbeat] ack #%d failed: %v", id, err)
		return
	}
	resp.Body.Close()
}
