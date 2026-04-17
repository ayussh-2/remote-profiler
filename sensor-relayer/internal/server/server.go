package server

import (
	"net/http"
	"time"

	"github.com/ayussh-2/profiler/sensor-relayer/internal/config"
	"github.com/ayussh-2/profiler/sensor-relayer/internal/handler"
	"github.com/ayussh-2/profiler/sensor-relayer/internal/models"
	"github.com/ayussh-2/profiler/sensor-relayer/internal/store"
)

func New(cfg config.Config, s *store.Store, m *models.Metrics, q chan *models.FusedPayload) *http.Server {
	relayer := handler.NewRelayer(s, m, q, cfg.FuseWindow, cfg.BackendURL)

	mux := http.NewServeMux()
	mux.HandleFunc("/", handler.Index)
	mux.HandleFunc("/api/frame", relayer.Frame)
	mux.HandleFunc("/api/depth", relayer.Depth)
	mux.HandleFunc("/api/gps", relayer.GPS)
	mux.HandleFunc("/api/metrics", relayer.Metrics)
	mux.HandleFunc("/api/config", relayer.ConfigHandler)
	mux.HandleFunc("/api/preview", relayer.Preview)
	mux.HandleFunc("/health", handler.Health)

	return &http.Server{
		Addr:         cfg.ListenAddr,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
	}
}
