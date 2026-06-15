package config

import (
	"os"
	"strconv"
)

type Config struct {
	ListenAddr  string
	DBPath      string
	JWTSecret   string
	JWTExpiryH  int
	DockerSocket string
}

func Load() *Config {
	return &Config{
		ListenAddr:   getEnv("LISTEN_ADDR", ":9000"),
		DBPath:       getEnv("DATABASE_PATH", "./orchestration.db"),
		JWTSecret:    getEnv("JWT_SECRET", "change-me-in-production-min-32-chars!!"),
		JWTExpiryH:   getEnvInt("JWT_EXPIRY_H", 8),
		DockerSocket: getEnv("DOCKER_SOCKET", "unix:///var/run/docker.sock"),
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if i, err := strconv.Atoi(v); err == nil {
			return i
		}
	}
	return fallback
}
