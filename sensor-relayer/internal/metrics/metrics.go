package metrics

import "github.com/ayussh-2/profiler/sensor-relayer/internal/models"

func Snapshot(m *models.Metrics) map[string]int64 {
	return map[string]int64{
		"frames_received": m.FramesReceived.Load(),
		"depth_received":  m.DepthReceived.Load(),
		"gps_received":    m.GPSReceived.Load(),
		"fuse_success":    m.FuseSuccess.Load(),
		"fuse_miss":       m.FuseMiss.Load(),
		"forward_success": m.ForwardSuccess.Load(),
		"forward_error":   m.ForwardError.Load(),
		"queue_dropped":   m.QueueDropped.Load(),
	}
}
