package models

import (
	"sync"
	"sync/atomic"
	"time"
)

type SensorFrame struct {
	ImageBytes []byte
	ReceivedAt time.Time
}

type DepthSample struct {
	DistanceMM float64
	ReceivedAt time.Time
}

type GPSSample struct {
	Lat        float64
	Lng        float64
	ReceivedAt time.Time
}

type FusedPayload struct {
	ImageBytes []byte
	DepthMM    float64
	Lat        float64
	Lng        float64
	FusedAt    time.Time
	TimeDiffMs int64
}

type Store struct {
	mu          sync.RWMutex
	LatestFrame *SensorFrame
	LatestDepth *DepthSample
	LatestGPS   *GPSSample
}

type Metrics struct {
	FramesReceived atomic.Int64
	DepthReceived  atomic.Int64
	GPSReceived    atomic.Int64
	FuseSuccess    atomic.Int64
	FuseMiss       atomic.Int64
	ForwardSuccess atomic.Int64
	ForwardError   atomic.Int64
	QueueDropped   atomic.Int64
}
