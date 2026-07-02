package main

import "testing"

func TestTunnelURLHTTPtoWS(t *testing.T) {
	got, err := tunnelURL("http://example.com", "control", "")
	if err != nil {
		t.Fatal(err)
	}
	want := "ws://example.com/api/edge/tunnel?role=control"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestTunnelURLHTTPStoWSS(t *testing.T) {
	got, err := tunnelURL("https://orchestration.redhusky.com.br", "data", "abc123")
	if err != nil {
		t.Fatal(err)
	}
	want := "wss://orchestration.redhusky.com.br/api/edge/tunnel?role=data&session_id=abc123"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestTunnelURLStripsTrailingSlash(t *testing.T) {
	got, err := tunnelURL("https://example.com/", "control", "")
	if err != nil {
		t.Fatal(err)
	}
	want := "wss://example.com/api/edge/tunnel?role=control"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}
