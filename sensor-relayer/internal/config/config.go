package config

import (
	"os"
	"strconv"
	"time"
)

type Config struct {
	ListenAddr     string
	BackendURL     string
	FuseWindow     time.Duration
	MaxFrameAge    time.Duration
	ForwardTimeout time.Duration
	WorkerCount    int
	QueueSize      int
}

func FromEnv() Config {
	getEnv := func(key, fallback string) string {
		if v := os.Getenv(key); v != "" {
			return v
		}
		return fallback
	}
	parseInt := func(key string, fallback int) int {
		if v := os.Getenv(key); v != "" {
			if n, err := strconv.Atoi(v); err == nil {
				return n
			}
		}
		return fallback
	}
	parseDur := func(key string, fallback time.Duration) time.Duration {
		if v := os.Getenv(key); v != "" {
			if d, err := time.ParseDuration(v); err == nil {
				return d
			}
		}
		return fallback
	}

	listenAddr := getEnv("RELAYER_ADDR", ":5001")
	if port := os.Getenv("PORT"); port != "" {
		listenAddr = ":" + port
	}

	return Config{
		ListenAddr:     listenAddr,
		BackendURL:     getEnv("BACKEND_URL", "http://localhost:5000/api/stream/frame"),
		FuseWindow:     parseDur("FUSE_WINDOW", 300*time.Millisecond),
		MaxFrameAge:    parseDur("MAX_FRAME_AGE", 2*time.Second),
		ForwardTimeout: parseDur("FORWARD_TIMEOUT", 5*time.Second),
		WorkerCount:    parseInt("WORKER_COUNT", 4),
		QueueSize:      parseInt("QUEUE_SIZE", 64),
	}
}
