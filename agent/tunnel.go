package main

import (
	"encoding/json"
	"log"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

type openStreamMsg struct {
	Cmd       string `json:"cmd"`
	SessionID string `json:"session_id"`
}

// runControlLoop holds one persistent WS to the hub and reconnects
// indefinitely on any drop — this connection being up is literally what the
// hub considers "online" for tunnel purposes (EdgeTunnelRegistry#online?).
func runControlLoop(cfg Config, token string) {
	for {
		if err := connectControl(cfg, token); err != nil {
			log.Printf("[tunnel] control channel error: %v", err)
		}
		time.Sleep(5 * time.Second)
	}
}

func tunnelURL(edgeURL, role, sessionID string) (string, error) {
	u, err := url.Parse(edgeURL)
	if err != nil {
		return "", err
	}
	switch u.Scheme {
	case "https":
		u.Scheme = "wss"
	default:
		u.Scheme = "ws"
	}
	u.Path = strings.TrimRight(u.Path, "/") + "/api/edge/tunnel"
	q := u.Query()
	q.Set("role", role)
	if sessionID != "" {
		q.Set("session_id", sessionID)
	}
	u.RawQuery = q.Encode()
	return u.String(), nil
}

func dialTunnel(cfg Config, token, role, sessionID string) (*websocket.Conn, error) {
	wsURL, err := tunnelURL(cfg.EdgeURL, role, sessionID)
	if err != nil {
		return nil, err
	}
	header := http.Header{}
	header.Set("Authorization", "Bearer "+token)
	conn, _, err := websocket.DefaultDialer.Dial(wsURL, header)
	return conn, err
}

func connectControl(cfg Config, token string) error {
	conn, err := dialTunnel(cfg, token, "control", "")
	if err != nil {
		return err
	}
	defer conn.Close()
	log.Printf("[tunnel] control channel connected")

	for {
		_, data, err := conn.ReadMessage()
		if err != nil {
			return err
		}

		var msg openStreamMsg
		if err := json.Unmarshal(data, &msg); err != nil {
			continue
		}
		if msg.Cmd == "open_stream" && msg.SessionID != "" {
			go handleOpenStream(cfg, token, msg.SessionID)
		}
	}
}

// handleOpenStream dials a brand-new outbound data WS for this one session
// and bridges it, byte for byte, to the local Docker socket — the hub's
// local TCP proxy on the other end is what makes this transparent to
// DockerClient/TtydManager (see Environment#effective_endpoint on the Rails
// side).
func handleOpenStream(cfg Config, token, sessionID string) {
	ws, err := dialTunnel(cfg, token, "data", sessionID)
	if err != nil {
		log.Printf("[tunnel] session %s: dial failed: %v", sessionID, err)
		return
	}
	defer ws.Close()

	sock, err := net.Dial("unix", cfg.DockerSock)
	if err != nil {
		log.Printf("[tunnel] session %s: docker socket dial failed: %v", sessionID, err)
		return
	}
	defer sock.Close()

	done := make(chan struct{}, 2)

	go func() {
		defer func() { done <- struct{}{} }()
		buf := make([]byte, 16384)
		for {
			n, err := sock.Read(buf)
			if n > 0 {
				if writeErr := ws.WriteMessage(websocket.BinaryMessage, buf[:n]); writeErr != nil {
					return
				}
			}
			if err != nil {
				return
			}
		}
	}()

	go func() {
		defer func() { done <- struct{}{} }()
		for {
			msgType, data, err := ws.ReadMessage()
			if err != nil {
				return
			}
			if msgType != websocket.BinaryMessage {
				continue
			}
			if _, err := sock.Write(data); err != nil {
				return
			}
		}
	}()

	<-done
}
