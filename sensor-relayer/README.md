# Sensor-Relayer

High-performance Go relay that ingests JPEG frames, depth values, and GPS coordinates from ESP32 sensors, fuses them by timestamp, and forwards to the ML backend for inference.

## Data Flow

```
ESP32-CAM                    Sensor-Relayer              Flask Backend
     |                             |                            |
     |--POST /api/frame----------->| (buffers frame)            |
     |   (JPEG binary)             |                            |
     |                             |                            |
     |--POST /api/depth----------->| (fuses frame+depth)        |
     |   (JSON: distance)     (within 300ms)                    |
     |                             |                            |
     |                             |--POST /api/stream/frame--->|
     |                             |   (multipart: image,       |
     |                             |    depth_mm, lat, lng)     |
     |                             |                            |
     |                             |<--204 No Content-----------|
     |                             |                            |
     |--POST /api/gps------------->| (enriches with location)   |
     |   (JSON: lat/lng)           |                            |
```

## Quick Start

```bash
make dev-relayer          # Run in development mode
make build-relayer        # Build binary
make docker-relayer       # Build Docker image
make simulate-relayer     # Run test simulator
```

## Project Structure

```
internal/
  ├── config/       Configuration loading from environment
  ├── models/       Data structures (SensorFrame, DepthSample, etc)
  ├── store/        State management and fusion logic
  ├── metrics/      Performance metrics
  ├── handler/      HTTP endpoint handlers
  ├── worker/       Forwarding workers and pool management
  └── server/       HTTP server setup

web/
  ├── static/       Dashboard HTML
  └── embed.go      Embeds HTML at compile time

pkg/utils/         Shared utilities
```

## Configuration

Set environment variables (or copy `.env.example`):

```bash
RELAYER_ADDR=:5001                                      # Listen address
BACKEND_URL=http://localhost:5000/api/stream/frame     # ML backend endpoint
FUSE_WINDOW=300ms                                       # Max time delta for fusion
MAX_FRAME_AGE=2s                                        # Drop old frames
FORWARD_TIMEOUT=5s                                      # HTTP timeout
WORKER_COUNT=4                                          # Parallel forwarders
QUEUE_SIZE=64                                           # Internal queue depth
PORT=<auto-set by Railway>                              # Override listen port
```

## Fusion Logic

Frames and depth samples are fused if they arrive within `FUSE_WINDOW` (default 300ms). The relayer:

1. **Stores** the latest frame, depth reading, and GPS coordinates in memory
2. **Attempts fusion** on every new frame or depth POST
3. **Succeeds** if both frame and depth exist and their timestamps are within the window
4. **Forwards** the fused payload (image + depth + GPS + metadata) to the ML backend
5. **Drops** the frame after fusion to avoid duplication

The window constraint ensures that frame and depth capture the same defect moment.

## API Endpoints

**POST /api/frame**

- Raw JPEG body or multipart form-data with "image" field
- Returns 204 No Content

**POST /api/depth**

- JSON: `{"distance": 123.4}` (millimeters)
- Returns 204 No Content

**POST /api/gps**

- JSON: `{"lat": 28.6, "lng": 77.2}`
- Returns 204 No Content

**GET /api/metrics**

- Returns JSON with counters and queue status

**GET /api/config** / **POST /api/config**

- View or update backend URL live

**GET /api/preview**

- Returns latest JPEG frame

**GET /**

- Dashboard UI

**GET /health**

- Health-check for load balancers/Docker

## Fusion Logic

Frames and depth samples are fused if they arrive within `FUSE_WINDOW` (default 300ms). Once fused, the frame is consumed and forwarded as multipart/form-data to the backend with:

- `image` — JPEG binary
- `depth_mm` — Depth in millimeters
- `lat`, `lng` — GPS coordinates (if available)
- `relayed_at` — Unix millisecond timestamp
- `time_diff_ms` — Frame-depth timestamp difference

## Development

```bash
# Run with live reload (requires entr or similar)
go run ./...

# Build
go build -o sensor-relayer

# Test with simulator
go run . &
python simulator.py

# Metrics endpoint
curl http://localhost:5001/api/metrics
```

## Docker

```bash
docker build -t sensor-relayer:latest .
docker run -p 5001:5001 \
  -e BACKEND_URL=http://host.docker.internal:5000/api/stream/frame \
  sensor-relayer:latest
```

## Performance

- Parallel worker pool (configurable, default 4)
- Lock-free atomic metrics
- Buffered channels with backpressure
- Connection pooling for backend forwarding
