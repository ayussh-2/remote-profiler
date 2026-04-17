package worker

import (
	"context"
	"log"
	"net/http"

	"github.com/ayussh-2/profiler/sensor-relayer/internal/models"
)

func Start(ctx context.Context, q chan *models.FusedPayload, m *models.Metrics, backendURL string, client *http.Client, workerCount int) {
	forwarder := NewForwarder(q, m, backendURL, client)
	for i := 0; i < workerCount; i++ {
		go worker(ctx, i, q, m, forwarder)
	}
}

func worker(ctx context.Context, id int, q chan *models.FusedPayload, m *models.Metrics, f *Forwarder) {
	for {
		select {
		case <-ctx.Done():
			return
		case p := <-q:
			if err := f.Forward(p); err != nil {
				m.ForwardError.Add(1)
				log.Printf("[worker-%d] forward error: %v", id, err)
			} else {
				m.ForwardSuccess.Add(1)
				log.Printf("[worker-%d] forwarded (depth=%.1fmm diff=%dms lat=%.5f lng=%.5f)",
					id, p.DepthMM, p.TimeDiffMs, p.Lat, p.Lng)
			}
		}
	}
}
