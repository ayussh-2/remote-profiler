package store

import (
	"sync"
	"time"

	"github.com/ayussh-2/profiler/sensor-relayer/internal/models"
)

type Store struct {
	mu          sync.RWMutex
	LatestFrame *models.SensorFrame
	LatestDepth *models.DepthSample
	LatestGPS   *models.GPSSample
}

func (s *Store) SetFrame(f *models.SensorFrame) {
	s.mu.Lock()
	s.LatestFrame = f
	s.mu.Unlock()
}

func (s *Store) SetDepth(d *models.DepthSample) {
	s.mu.Lock()
	s.LatestDepth = d
	s.mu.Unlock()
}

func (s *Store) SetGPS(g *models.GPSSample) {
	s.mu.Lock()
	s.LatestGPS = g
	s.mu.Unlock()
}

func (s *Store) GetLatestFrame() *models.SensorFrame {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.LatestFrame
}

func (s *Store) TryFuse(window time.Duration) (*models.FusedPayload, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.LatestFrame == nil || s.LatestDepth == nil {
		return nil, false
	}

	diff := s.LatestFrame.ReceivedAt.Sub(s.LatestDepth.ReceivedAt)
	if diff < 0 {
		diff = -diff
	}
	if diff > window {
		return nil, false
	}

	lat, lng := 0.0, 0.0
	if s.LatestGPS != nil {
		lat = s.LatestGPS.Lat
		lng = s.LatestGPS.Lng
	}

	p := &models.FusedPayload{
		ImageBytes: s.LatestFrame.ImageBytes,
		DepthMM:    s.LatestDepth.DistanceMM,
		Lat:        lat,
		Lng:        lng,
		FusedAt:    time.Now(),
		TimeDiffMs: diff.Milliseconds(),
	}

	s.LatestFrame = nil

	return p, true
}
