package main

import (
	"fmt"
	"os"
	"runtime"
	"strconv"
	"time"
)

const AgentVersion = "0.1.0"

type Config struct {
	EdgeURL            string
	EnrollmentToken    string
	TokenFile          string
	DockerSock         string
	HeartbeatInterval  time.Duration
	OS                 string
	Arch               string
}

func loadConfig() (Config, error) {
	url := os.Getenv("EDGE_URL")
	if url == "" {
		return Config{}, fmt.Errorf("EDGE_URL is required")
	}

	interval := 30
	if v := os.Getenv("HEARTBEAT_INTERVAL"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			interval = n
		}
	}

	tokenFile := os.Getenv("EDGE_TOKEN_FILE")
	if tokenFile == "" {
		tokenFile = "/data/edge-token"
	}

	dockerSock := os.Getenv("DOCKER_SOCK")
	if dockerSock == "" {
		dockerSock = "/var/run/docker.sock"
	}

	return Config{
		EdgeURL:           url,
		EnrollmentToken:   os.Getenv("EDGE_ENROLLMENT_TOKEN"),
		TokenFile:         tokenFile,
		DockerSock:        dockerSock,
		HeartbeatInterval: time.Duration(interval) * time.Second,
		OS:                runtime.GOOS,
		Arch:              runtime.GOARCH,
	}, nil
}
