package main

import (
	"bufio"
	"math"
	"os"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type Metrics struct {
	CPUPercent  float64
	RAMPercent  float64
	DiskPercent float64
	SwapPercent float64
	Load1       float64
	Load5       float64
	Load15      float64
}

func round1(v float64) float64 {
	return math.Round(v*10) / 10
}

func collectMetrics(procPath string) Metrics {
	return Metrics{
		CPUPercent:  cpuPercent(procPath),
		RAMPercent:  ramPercent(procPath),
		DiskPercent: diskPercent("/"),
		SwapPercent: swapPercent(procPath),
		Load1:       loadAvg(procPath, 0),
		Load5:       loadAvg(procPath, 1),
		Load15:      loadAvg(procPath, 2),
	}
}

// Same delta-over-1s sampling MetricsJob uses on the Rails side (a single
// /proc/stat read gives a cumulative counter since boot, not a percentage).
func cpuPercent(procPath string) float64 {
	s1, ok1 := readCPUStat(procPath)
	time.Sleep(1 * time.Second)
	s2, ok2 := readCPUStat(procPath)
	if !ok1 || !ok2 {
		return 0
	}

	var total1, total2 float64
	for _, v := range s1 {
		total1 += v
	}
	for _, v := range s2 {
		total2 += v
	}
	totalDelta := total2 - total1
	idleDelta := s2[3] - s1[3]
	if totalDelta == 0 {
		return 0
	}
	return round1((1.0 - idleDelta/totalDelta) * 100)
}

func readCPUStat(procPath string) ([]float64, bool) {
	f, err := os.Open(procPath + "/stat")
	if err != nil {
		return nil, false
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	if !scanner.Scan() {
		return nil, false
	}
	fields := strings.Fields(scanner.Text())
	if len(fields) < 5 {
		return nil, false
	}
	values := make([]float64, 0, len(fields)-1)
	for _, field := range fields[1:] {
		n, err := strconv.ParseFloat(field, 64)
		if err != nil {
			return nil, false
		}
		values = append(values, n)
	}
	return values, true
}

func parseMeminfo(procPath string) map[string]float64 {
	result := map[string]float64{}
	f, err := os.Open(procPath + "/meminfo")
	if err != nil {
		return result
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) < 2 {
			continue
		}
		key := strings.TrimSuffix(fields[0], ":")
		if n, err := strconv.ParseFloat(fields[1], 64); err == nil {
			result[key] = n
		}
	}
	return result
}

func ramPercent(procPath string) float64 {
	mem := parseMeminfo(procPath)
	total := mem["MemTotal"]
	available := mem["MemAvailable"]
	if total == 0 {
		return 0
	}
	return round1((total - available) / total * 100)
}

func swapPercent(procPath string) float64 {
	mem := parseMeminfo(procPath)
	total := mem["SwapTotal"]
	free := mem["SwapFree"]
	if total == 0 {
		return 0
	}
	return round1((total - free) / total * 100)
}

func diskPercent(path string) float64 {
	var stat syscall.Statfs_t
	if err := syscall.Statfs(path, &stat); err != nil {
		return 0
	}
	total := float64(stat.Blocks) * float64(stat.Bsize)
	free := float64(stat.Bfree) * float64(stat.Bsize)
	if total == 0 {
		return 0
	}
	return round1((total - free) / total * 100)
}

func loadAvg(procPath string, index int) float64 {
	data, err := os.ReadFile(procPath + "/loadavg")
	if err != nil {
		return 0
	}
	fields := strings.Fields(string(data))
	if len(fields) <= index {
		return 0
	}
	n, err := strconv.ParseFloat(fields[index], 64)
	if err != nil {
		return 0
	}
	return n
}
