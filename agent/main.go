// redhusk-edge-agent: a single static binary that enrolls with a
// redhusk-orchestration hub, reports heartbeat/metrics, and tunnels the
// hub's Docker API calls to this host's local docker.sock — entirely via
// outbound connections, so it never needs an open port.
package main

import "log"

func main() {
	log.SetFlags(log.LstdFlags | log.Lmsgprefix)
	log.SetPrefix("[agent] ")

	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("config error: %v", err)
	}

	token, err := ensureEnrolled(cfg)
	if err != nil {
		log.Fatalf("enrollment error: %v", err)
	}
	log.Printf("enrolled, token persisted at %s", cfg.TokenFile)

	go runControlLoop(cfg, token)
	runHeartbeatLoop(cfg, token)
}
