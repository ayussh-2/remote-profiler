package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/ayussh-2/profiler/sensor-relayer/internal/config"
	"github.com/ayussh-2/profiler/sensor-relayer/internal/models"
	"github.com/ayussh-2/profiler/sensor-relayer/internal/server"
	"github.com/ayussh-2/profiler/sensor-relayer/internal/store"
	"github.com/ayussh-2/profiler/sensor-relayer/internal/worker"
)

func main() {
	cfg := config.FromEnv()

	log.SetFlags(log.Ltime | log.Lmicroseconds)
	log.Printf("sensor-relayer starting on %s", cfg.ListenAddr)
	log.Printf("   backend   -> %s", cfg.BackendURL)
	log.Printf("   fuse_win  -> %v", cfg.FuseWindow)
	log.Printf("   workers   -> %d", cfg.WorkerCount)
	log.Printf("   dashboard -> http://localhost%s/", cfg.ListenAddr)

	s := &store.Store{}
	m := &models.Metrics{}
	q := make(chan *models.FusedPayload, cfg.QueueSize)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	client := &http.Client{
		Timeout: cfg.ForwardTimeout,
		Transport: &http.Transport{
			MaxIdleConnsPerHost: cfg.WorkerCount * 2,
			IdleConnTimeout:     30 * time.Second,
		},
	}
	worker.Start(ctx, q, m, cfg.BackendURL, client, cfg.WorkerCount)

	srv := server.New(cfg, s, m, q)

	go func() {
		sig := make(chan os.Signal, 1)
		signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
		<-sig
		log.Println("shutting down...")
		cancel()
		shutCtx, shutCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer shutCancel()
		srv.Shutdown(shutCtx)
	}()

	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("server error: %v", err)
	}
	log.Println("server stopped cleanly")
}
