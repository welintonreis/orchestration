package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// ensureEnrolled returns the node's permanent token, enrolling with the hub
// on first run (EDGE_ENROLLMENT_TOKEN) and persisting it to disk so restarts
// don't need a fresh enrollment token.
func ensureEnrolled(cfg Config) (string, error) {
	if data, err := os.ReadFile(cfg.TokenFile); err == nil {
		token := strings.TrimSpace(string(data))
		if token != "" {
			return token, nil
		}
	}

	if cfg.EnrollmentToken == "" {
		return "", fmt.Errorf("no saved token in %s and EDGE_ENROLLMENT_TOKEN not set", cfg.TokenFile)
	}

	form := url.Values{
		"enrollment_token": {cfg.EnrollmentToken},
		"agent_version":    {AgentVersion},
		"os":               {cfg.OS},
		"arch":             {cfg.Arch},
	}

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.PostForm(strings.TrimRight(cfg.EdgeURL, "/")+"/api/edge/enroll", form)
	if err != nil {
		return "", fmt.Errorf("enroll request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		return "", fmt.Errorf("enroll rejected: HTTP %d", resp.StatusCode)
	}

	var body struct {
		NodeToken string `json:"node_token"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return "", fmt.Errorf("enroll response decode failed: %w", err)
	}
	if body.NodeToken == "" {
		return "", fmt.Errorf("enroll response missing node_token")
	}

	if dir := filepath.Dir(cfg.TokenFile); dir != "." {
		_ = os.MkdirAll(dir, 0o700)
	}
	if err := os.WriteFile(cfg.TokenFile, []byte(body.NodeToken), 0o600); err != nil {
		return "", fmt.Errorf("saving token failed: %w", err)
	}

	return body.NodeToken, nil
}
