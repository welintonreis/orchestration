package main

import (
	"os"
	"path/filepath"
	"testing"
)

func fakeProc(t *testing.T, files map[string]string) string {
	t.Helper()
	dir := t.TempDir()
	for name, content := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func TestRamPercent(t *testing.T) {
	dir := fakeProc(t, map[string]string{
		"meminfo": "MemTotal:       1000000 kB\nMemAvailable:    250000 kB\n",
	})
	got := ramPercent(dir)
	if got != 75.0 {
		t.Errorf("got %v, want 75.0", got)
	}
}

func TestRamPercentZeroTotal(t *testing.T) {
	dir := fakeProc(t, map[string]string{"meminfo": "MemTotal:       0 kB\n"})
	if got := ramPercent(dir); got != 0 {
		t.Errorf("got %v, want 0", got)
	}
}

func TestSwapPercent(t *testing.T) {
	dir := fakeProc(t, map[string]string{
		"meminfo": "SwapTotal:      2000000 kB\nSwapFree:       500000 kB\n",
	})
	got := swapPercent(dir)
	if got != 75.0 {
		t.Errorf("got %v, want 75.0", got)
	}
}

func TestLoadAvg(t *testing.T) {
	dir := fakeProc(t, map[string]string{"loadavg": "0.10 0.25 0.50 1/200 12345\n"})
	if got := loadAvg(dir, 0); got != 0.10 {
		t.Errorf("load1: got %v, want 0.10", got)
	}
	if got := loadAvg(dir, 1); got != 0.25 {
		t.Errorf("load5: got %v, want 0.25", got)
	}
	if got := loadAvg(dir, 2); got != 0.50 {
		t.Errorf("load15: got %v, want 0.50", got)
	}
}

func TestLoadAvgMissingFile(t *testing.T) {
	dir := t.TempDir()
	if got := loadAvg(dir, 0); got != 0 {
		t.Errorf("got %v, want 0", got)
	}
}

func TestDiskPercentRealRoot(t *testing.T) {
	// "/" always exists on the test runner — just sanity-check the range,
	// since exact usage is environment-dependent.
	got := diskPercent("/")
	if got < 0 || got > 100 {
		t.Errorf("disk percent out of range: %v", got)
	}
}
