// sensor-relayer/main.go
//
// High-performance Go relay that ingests:
//   • JPEG frames  from ESP32-CAM  → POST /api/frame  (multipart or raw body)
//   • Depth values from ESP32-DEV  → POST /api/depth  (JSON)
//   • GPS coords   from either ESP → POST /api/gps    (JSON)
//
// It fuses frame + depth by timestamp (configurable window) and
// forwards the combined multipart payload to the main backend for ML inference.

package main

import (
	"bytes"
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"mime/multipart"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

//go:embed index.html
var indexHTML []byte

// ─── Configuration ────────────────────────────────────────────────────────────

type Config struct {
	ListenAddr     string        // e.g. ":5001"
	BackendURL     string        // e.g. "http://localhost:5000/stream/frame"
	FuseWindow     time.Duration // max age-diff between frame and depth to fuse
	MaxFrameAge    time.Duration // drop frame if no matching depth arrives in time
	ForwardTimeout time.Duration // HTTP timeout for forwarding to backend
	WorkerCount    int           // parallel forwarder goroutines
	QueueSize      int           // buffered channel depth for fused payloads
}

func configFromEnv() Config {
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
		listenAddr = ":" + port // Railway dynamic port support
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

// ─── Data Types ───────────────────────────────────────────────────────────────

type SensorFrame struct {
	imageBytes []byte
	receivedAt time.Time
}

type DepthSample struct {
	distanceMM float64
	receivedAt time.Time
}

type GPSSample struct {
	lat        float64
	lng        float64
	receivedAt time.Time
}

// FusedPayload is what gets forwarded to the ML backend.
type FusedPayload struct {
	imageBytes []byte
	depthMM    float64
	lat        float64
	lng        float64
	fusedAt    time.Time
	timeDiffMs int64 // age difference between frame and depth at fusion
}

// ─── State Store ──────────────────────────────────────────────────────────────

type Store struct {
	mu          sync.RWMutex
	latestFrame *SensorFrame
	latestDepth *DepthSample
	latestGPS   *GPSSample
}

func (s *Store) SetFrame(f *SensorFrame) {
	s.mu.Lock()
	s.latestFrame = f
	s.mu.Unlock()
}

func (s *Store) SetDepth(d *DepthSample) {
	s.mu.Lock()
	s.latestDepth = d
	s.mu.Unlock()
}

func (s *Store) SetGPS(g *GPSSample) {
	s.mu.Lock()
	s.latestGPS = g
	s.mu.Unlock()
}

// TryFuse attempts to match the latest frame + depth within the fusion window.
// Returns (payload, true) on success, (nil, false) if no valid match.
func (s *Store) TryFuse(window time.Duration) (*FusedPayload, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.latestFrame == nil || s.latestDepth == nil {
		return nil, false
	}

	diff := s.latestFrame.receivedAt.Sub(s.latestDepth.receivedAt)
	if diff < 0 {
		diff = -diff
	}
	if diff > window {
		return nil, false
	}

	lat, lng := 0.0, 0.0
	if s.latestGPS != nil {
		lat = s.latestGPS.lat
		lng = s.latestGPS.lng
	}

	p := &FusedPayload{
		imageBytes: s.latestFrame.imageBytes,
		depthMM:    s.latestDepth.distanceMM,
		lat:        lat,
		lng:        lng,
		fusedAt:    time.Now(),
		timeDiffMs: diff.Milliseconds(),
	}

	// Consume frame so the same frame isn't forwarded twice.
	s.latestFrame = nil

	return p, true
}

// ─── Metrics ──────────────────────────────────────────────────────────────────

type Metrics struct {
	framesReceived atomic.Int64
	depthReceived  atomic.Int64
	gpsReceived    atomic.Int64
	fuseSuccess    atomic.Int64
	fuseMiss       atomic.Int64
	forwardSuccess atomic.Int64
	forwardError   atomic.Int64
	queueDropped   atomic.Int64
}

func (m *Metrics) Snapshot() map[string]int64 {
	return map[string]int64{
		"frames_received": m.framesReceived.Load(),
		"depth_received":  m.depthReceived.Load(),
		"gps_received":    m.gpsReceived.Load(),
		"fuse_success":    m.fuseSuccess.Load(),
		"fuse_miss":       m.fuseMiss.Load(),
		"forward_success": m.forwardSuccess.Load(),
		"forward_error":   m.forwardError.Load(),
		"queue_dropped":   m.queueDropped.Load(),
	}
}

// ─── Relayer Server ───────────────────────────────────────────────────────────

type Relayer struct {
	cfg        Config
	backendURL string
	urlMu      sync.RWMutex
	store      *Store
	metrics    *Metrics
	queue      chan *FusedPayload
	client     *http.Client
}

func NewRelayer(cfg Config) *Relayer {
	return &Relayer{
		cfg:        cfg,
		backendURL: cfg.BackendURL,
		store:      &Store{},
		metrics:    &Metrics{},
		queue:      make(chan *FusedPayload, cfg.QueueSize),
		client: &http.Client{
			Timeout: cfg.ForwardTimeout,
			Transport: &http.Transport{
				MaxIdleConnsPerHost: cfg.WorkerCount * 2,
				IdleConnTimeout:     30 * time.Second,
			},
		},
	}
}

func (r *Relayer) getBackendURL() string {
	r.urlMu.RLock()
	defer r.urlMu.RUnlock()
	return r.backendURL
}

func (r *Relayer) setBackendURL(u string) {
	r.urlMu.Lock()
	defer r.urlMu.Unlock()
	r.backendURL = u
}

// ── Handlers ──────────────────────────────────────────────────────────────────

// POST /api/frame  — accepts raw JPEG body OR multipart/form-data with "image" field
func (r *Relayer) handleFrame(w http.ResponseWriter, req *http.Request) {
	if req.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var imageBytes []byte
	ct := req.Header.Get("Content-Type")

	if ct == "image/jpeg" || ct == "application/octet-stream" {
		// Raw binary body (most ESP32-CAM firmware default)
		data, err := io.ReadAll(io.LimitReader(req.Body, 2<<20)) // 2 MB cap
		if err != nil || len(data) == 0 {
			http.Error(w, "empty body", http.StatusBadRequest)
			return
		}
		imageBytes = data
	} else {
		// Multipart: look for "image" field
		if err := req.ParseMultipartForm(2 << 20); err != nil {
			http.Error(w, "parse error", http.StatusBadRequest)
			return
		}
		f, _, err := req.FormFile("image")
		if err != nil {
			http.Error(w, "missing image field", http.StatusBadRequest)
			return
		}
		defer f.Close()
		data, err := io.ReadAll(io.LimitReader(f, 2<<20))
		if err != nil || len(data) == 0 {
			http.Error(w, "empty image", http.StatusBadRequest)
			return
		}
		imageBytes = data
	}

	frame := &SensorFrame{
		imageBytes: imageBytes,
		receivedAt: time.Now(),
	}
	r.store.SetFrame(frame)
	r.metrics.framesReceived.Add(1)

	// Try immediate fusion after every new frame
	r.tryEnqueue()

	w.WriteHeader(http.StatusNoContent)
}

// POST /api/depth  — JSON: {"distance": 123.4}  (distance in mm)
func (r *Relayer) handleDepth(w http.ResponseWriter, req *http.Request) {
	if req.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var payload struct {
		Distance float64 `json:"distance"`
		DepthMM  float64 `json:"depth_mm"` // alternate key
	}
	if err := json.NewDecoder(io.LimitReader(req.Body, 1024)).Decode(&payload); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}

	distanceMM := payload.Distance
	if distanceMM == 0 {
		distanceMM = payload.DepthMM
	}
	if distanceMM <= 0 {
		// allow 0 or below as invalid readings but don't error, or just return error
	}

	r.store.SetDepth(&DepthSample{
		distanceMM: distanceMM,
		receivedAt: time.Now(),
	})
	r.metrics.depthReceived.Add(1)

	// Try fusion after every new depth reading too
	r.tryEnqueue()

	w.WriteHeader(http.StatusNoContent)
}

// POST /api/gps  — JSON: {"lat": 28.6, "lng": 77.2}
func (r *Relayer) handleGPS(w http.ResponseWriter, req *http.Request) {
	if req.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var payload struct {
		Lat float64 `json:"lat"`
		Lng float64 `json:"lng"`
		Lon float64 `json:"lon"` // alternate spelling
	}
	if err := json.NewDecoder(io.LimitReader(req.Body, 256)).Decode(&payload); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}

	lng := payload.Lng
	if lng == 0 {
		lng = payload.Lon
	}

	r.store.SetGPS(&GPSSample{
		lat:        payload.Lat,
		lng:        lng,
		receivedAt: time.Now(),
	})
	r.metrics.gpsReceived.Add(1)
	w.WriteHeader(http.StatusNoContent)
}

// GET /api/metrics  — quick health + stats check
func (r *Relayer) handleMetrics(w http.ResponseWriter, req *http.Request) {
	snap := r.metrics.Snapshot()
	snap["queue_len"] = int64(len(r.queue))
	snap["queue_cap"] = int64(cap(r.queue))
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(snap)
}

// GET or POST /api/config — update backend url live
func (r *Relayer) handleConfig(w http.ResponseWriter, req *http.Request) {
	if req.Method == http.MethodGet {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"backend_url": r.getBackendURL()})
		return
	}
	if req.Method == http.MethodPost {
		var payload struct {
			BackendURL string `json:"backend_url"`
		}
		if err := json.NewDecoder(io.LimitReader(req.Body, 1024)).Decode(&payload); err != nil {
			http.Error(w, "bad config req", http.StatusBadRequest)
			return
		}
		r.setBackendURL(payload.BackendURL)
		w.WriteHeader(http.StatusOK)
		fmt.Println("🔄 Backend URL updated to:", payload.BackendURL)
	}
}

// GET /api/preview — returns latest frame as jpeg
func (r *Relayer) handlePreview(w http.ResponseWriter, req *http.Request) {
	r.store.mu.RLock()
	var frameBytes []byte
	if r.store.latestFrame != nil {
		frameBytes = r.store.latestFrame.imageBytes
	}
	r.store.mu.RUnlock()

	if len(frameBytes) == 0 {
		http.Error(w, "no frame yet", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "image/jpeg")
	w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate")
	w.Write(frameBytes)
}

// GET / — render dashboard
func handleIndex(w http.ResponseWriter, req *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write(indexHTML)
}

// ── Fusion + Forwarding ───────────────────────────────────────────────────────

// tryEnqueue attempts a fusion and pushes the result onto the worker queue.
func (r *Relayer) tryEnqueue() {
	p, ok := r.store.TryFuse(r.cfg.FuseWindow)
	if !ok {
		r.metrics.fuseMiss.Add(1)
		return
	}
	r.metrics.fuseSuccess.Add(1)

	select {
	case r.queue <- p:
		// queued successfully
	default:
		// queue full — drop and count
		r.metrics.queueDropped.Add(1)
		log.Printf("[relayer] ⚠  queue full — dropping fused frame (depth=%.1fmm diff=%dms)",
			p.depthMM, p.timeDiffMs)
	}
}

// startWorkers launches N goroutines that drain the fusion queue.
func (r *Relayer) startWorkers(ctx context.Context) {
	for i := 0; i < r.cfg.WorkerCount; i++ {
		go func(id int) {
			for {
				select {
				case <-ctx.Done():
					return
				case p := <-r.queue:
					if err := r.forwardPayload(p); err != nil {
						r.metrics.forwardError.Add(1)
						log.Printf("[worker-%d] ✗ forward error: %v", id, err)
					} else {
						r.metrics.forwardSuccess.Add(1)
						log.Printf("[worker-%d] ✓ forwarded (depth=%.1fmm diff=%dms lat=%.5f lng=%.5f)",
							id, p.depthMM, p.timeDiffMs, p.lat, p.lng)
					}
				}
			}
		}(i)
	}
}

// forwardPayload builds a multipart/form-data request identical to what
// the Python backend's /stream/frame endpoint expects and sends it.
func (r *Relayer) forwardPayload(p *FusedPayload) error {
	var body bytes.Buffer
	mw := multipart.NewWriter(&body)

	// image field
	fw, err := mw.CreateFormFile("image", "frame.jpg")
	if err != nil {
		return fmt.Errorf("create form file: %w", err)
	}
	if _, err = fw.Write(p.imageBytes); err != nil {
		return fmt.Errorf("write image: %w", err)
	}

	// numeric fields
	fields := map[string]string{
		"depth_mm":     strconv.FormatFloat(p.depthMM, 'f', 2, 64),
		"lat":          strconv.FormatFloat(p.lat, 'f', 7, 64),
		"lng":          strconv.FormatFloat(p.lng, 'f', 7, 64),
		"relayed_at":   strconv.FormatInt(p.fusedAt.UnixMilli(), 10),
		"time_diff_ms": strconv.FormatInt(p.timeDiffMs, 10),
	}
	for k, v := range fields {
		if err = mw.WriteField(k, v); err != nil {
			return fmt.Errorf("write field %s: %w", k, err)
		}
	}

	if err = mw.Close(); err != nil {
		return fmt.Errorf("close writer: %w", err)
	}

	backendURL := r.getBackendURL()
	req, err := http.NewRequest(http.MethodPost, backendURL, &body)
	if err != nil {
		return fmt.Errorf("new request: %w", err)
	}
	req.Header.Set("Content-Type", mw.FormDataContentType())

	resp, err := r.client.Do(req)
	if err != nil {
		return fmt.Errorf("http do: %w", err)
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, resp.Body)

	if resp.StatusCode >= 300 {
		return fmt.Errorf("backend returned %s", resp.Status)
	}
	return nil
}

// ─── Main ─────────────────────────────────────────────────────────────────────

func main() {
	cfg := configFromEnv()

	log.SetFlags(log.Ltime | log.Lmicroseconds)
	log.Printf("🚀 sensor-relayer starting on %s", cfg.ListenAddr)
	log.Printf("   backend   → %s", cfg.BackendURL)
	log.Printf("   fuse_win  → %v", cfg.FuseWindow)
	log.Printf("   workers   → %d", cfg.WorkerCount)
	log.Printf("   dashboard → http://localhost%s/", cfg.ListenAddr)

	relayer := NewRelayer(cfg)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	relayer.startWorkers(ctx)

	mux := http.NewServeMux()
	mux.HandleFunc("/", handleIndex)
	mux.HandleFunc("/api/frame", relayer.handleFrame)
	mux.HandleFunc("/api/depth", relayer.handleDepth)
	mux.HandleFunc("/api/gps", relayer.handleGPS)
	mux.HandleFunc("/api/metrics", relayer.handleMetrics)
	mux.HandleFunc("/api/config", relayer.handleConfig)
	mux.HandleFunc("/api/preview", relayer.handlePreview)

	// Health-check used by load balancers / Docker healthcheck
	mux.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprintln(w, "ok")
	})

	srv := &http.Server{
		Addr:         cfg.ListenAddr,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Graceful shutdown on SIGINT / SIGTERM
	go func() {
		sig := make(chan os.Signal, 1)
		signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
		<-sig
		log.Println("⏹  shutting down…")
		cancel()
		shutCtx, shutCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer shutCancel()
		srv.Shutdown(shutCtx)
	}()

	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("server error: %v", err)
	}
	log.Println("✓ server stopped cleanly")
}
