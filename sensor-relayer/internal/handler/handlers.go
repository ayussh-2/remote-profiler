package handler

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"

	"github.com/ayussh-2/profiler/sensor-relayer/internal/metrics"
	"github.com/ayussh-2/profiler/sensor-relayer/internal/models"
	"github.com/ayussh-2/profiler/sensor-relayer/internal/store"
	"github.com/ayussh-2/profiler/sensor-relayer/web"
)

type Relayer struct {
	store      *store.Store
	metrics    *models.Metrics
	queue      chan *models.FusedPayload
	fuseWindow time.Duration
	backendURL string
}

func NewRelayer(s *store.Store, m *models.Metrics, q chan *models.FusedPayload, fw time.Duration, backendURL string) *Relayer {
	return &Relayer{
		store:      s,
		metrics:    m,
		queue:      q,
		fuseWindow: fw,
		backendURL: backendURL,
	}
}

func (r *Relayer) Frame(w http.ResponseWriter, req *http.Request) {
	if req.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var imageBytes []byte
	ct := req.Header.Get("Content-Type")

	if ct == "image/jpeg" || ct == "application/octet-stream" {
		data, err := io.ReadAll(io.LimitReader(req.Body, 2<<20))
		if err != nil || len(data) == 0 {
			http.Error(w, "empty body", http.StatusBadRequest)
			return
		}
		imageBytes = data
	} else {
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

	frame := &models.SensorFrame{
		ImageBytes: imageBytes,
		ReceivedAt: time.Now(),
	}
	r.store.SetFrame(frame)
	r.metrics.FramesReceived.Add(1)
	r.tryEnqueue()
	w.WriteHeader(http.StatusNoContent)
}

func (r *Relayer) Depth(w http.ResponseWriter, req *http.Request) {
	if req.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var payload struct {
		Distance float64 `json:"distance"`
		DepthMM  float64 `json:"depth_mm"`
	}
	if err := json.NewDecoder(io.LimitReader(req.Body, 1024)).Decode(&payload); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}

	distanceMM := payload.Distance
	if distanceMM == 0 {
		distanceMM = payload.DepthMM
	}

	r.store.SetDepth(&models.DepthSample{
		DistanceMM: distanceMM,
		ReceivedAt: time.Now(),
	})
	r.metrics.DepthReceived.Add(1)
	r.tryEnqueue()
	w.WriteHeader(http.StatusNoContent)
}

func (r *Relayer) GPS(w http.ResponseWriter, req *http.Request) {
	if req.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var payload struct {
		Lat float64 `json:"lat"`
		Lng float64 `json:"lng"`
		Lon float64 `json:"lon"`
	}
	if err := json.NewDecoder(io.LimitReader(req.Body, 256)).Decode(&payload); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}

	lng := payload.Lng
	if lng == 0 {
		lng = payload.Lon
	}

	r.store.SetGPS(&models.GPSSample{
		Lat:        payload.Lat,
		Lng:        lng,
		ReceivedAt: time.Now(),
	})
	r.metrics.GPSReceived.Add(1)
	w.WriteHeader(http.StatusNoContent)
}

func (r *Relayer) Metrics(w http.ResponseWriter, req *http.Request) {
	snap := metrics.Snapshot(r.metrics)
	snap["queue_len"] = int64(len(r.queue))
	snap["queue_cap"] = int64(cap(r.queue))
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(snap)
}

func (r *Relayer) ConfigHandler(w http.ResponseWriter, req *http.Request) {
	if req.Method == http.MethodGet {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"backend_url": r.backendURL})
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
		r.backendURL = payload.BackendURL
		w.WriteHeader(http.StatusOK)
		fmt.Println("Backend URL updated to:", payload.BackendURL)
	}
}

func (r *Relayer) Preview(w http.ResponseWriter, req *http.Request) {
	frame := r.store.GetLatestFrame()
	if frame == nil {
		http.Error(w, "no frame yet", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "image/jpeg")
	w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate")
	w.Write(frame.ImageBytes)
}

func Index(w http.ResponseWriter, req *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write(web.IndexHTML)
}

func Health(w http.ResponseWriter, req *http.Request) {
	w.WriteHeader(http.StatusOK)
	fmt.Fprintln(w, "ok")
}

func (r *Relayer) tryEnqueue() {
	p, ok := r.store.TryFuse(r.fuseWindow)
	if !ok {
		r.metrics.FuseMiss.Add(1)
		return
	}
	r.metrics.FuseSuccess.Add(1)

	select {
	case r.queue <- p:
	default:
		r.metrics.QueueDropped.Add(1)
		log.Printf("[handler] queue full — dropping fused frame (depth=%.1fmm diff=%dms)",
			p.DepthMM, p.TimeDiffMs)
	}
}
