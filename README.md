# Pavement Profiler

**Automated Road Defect Detection & Volume Estimation System**

A low-cost, sensor-fused road assessment robot that replaces subjective manual inspection with objective, repeatable, geotagged engineering data.

## System Overview

```
┌─────────────────────────────┐
│      RC Robot Unit          │
│  ┌──────────┐  ┌─────────┐  │
│  │ESP32-CAM │→ │VL53L1X  │  │
│  │(frames)  │  │(depth)  │  │
│  └──────────┘  └─────────┘  │
└────────────────┬────────────┘
                 │ WiFi: /api/frame, /api/depth, /api/gps
                 ↓
    ┌────────────────────────────────┐
    │    Sensor-Relayer (Go)         │
    │  Port :5001                    │
    │  • Fuses frame + depth         │
    │  • Buffers with workers        │
    │  • Metrics endpoint            │
    └────────────┬───────────────────┘
                 │ HTTP POST: multipart with fused data
                 ↓
    ┌────────────────────────────────┐
    │   Flask Backend (Python)       │
    │  Port :5000                    │
    │  • YOLOv8 detection            │
    │  • Material estimation         │
    │  • Google Sheets logging       │
    └────────────┬───────────────────┘
                 │ JSON response + annotated image
                 ↓
    ┌────────────────────────────────┐
    │   React Dashboard (Frontend)   │
    │  Port :5173                    │
    │  • Live detection results      │
    │  • Leaflet map with pins       │
    │  • Logs table (from Sheets)    │
    └────────────────────────────────┘
```

## Quick Start

**Prerequisites:** Go 1.22+, Python 3.9+, Node.js (for web)

### 1. Set Up Backend

```bash
cd backend
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
python app.py              # Runs on http://localhost:5000
```

### 2. Run Sensor-Relayer

```bash
cd sensor-relayer
go build -o sensor-relayer
./sensor-relayer            # Runs on http://localhost:5001
```

Environment: Copy `.env.example` to `.env` and adjust `BACKEND_URL`, `WORKER_COUNT`, etc.

### 3. Start Frontend Dashboard

```bash
cd frontend
bun install
bun dev                     # Runs on http://localhost:5173
```

### 4. Test with Simulator

```bash
cd sensor-relayer
python simulator.py         # Sends fake ESP32 frames/depth to relayer
```

Or use the Makefile:

```bash
make dev-server             # Backend
make dev-relayer            # Relayer
make dev-frontend           # Frontend
make simulate-relayer       # Test simulator
```

## Architecture

### Components

| Component           | Language     | Role                                 | Docs                                                 |
| ------------------- | ------------ | ------------------------------------ | ---------------------------------------------------- |
| **RC Robot**        | C (ESP32)    | Captures frames + depth              | [Hardware Design](#hardware-design)                  |
| **Sensor-Relayer**  | Go           | Fuses sensors, buffers, forwards     | [sensor-relayer/README.md](sensor-relayer/README.md) |
| **Backend (Flask)** | Python       | YOLO inference + material estimation | [docs/ARCHITECTURE.MD](docs/ARCHITECTURE.MD)         |
| **Frontend**        | React + Vite | Dashboard UI, maps, logs             | [frontend/README.md](frontend/README.md)             |

## Data Flow

```
ESP32 Robot
  ├─→ POST /api/frame (JPEG) ──┐
  ├─→ POST /api/depth (JSON)   │
  └─→ POST /api/gps (JSON)     │
                               ↓
                    Sensor-Relayer :5001
                    (fusion window: 300ms)
                               │
                  POST /api/stream/frame
                  (multipart: image + depth_mm + lat/lng)
                               ↓
                    Flask Backend :5000
                    (YOLOv8 + Material Estimator)
                               │
                    Append to Google Sheets
                    + Return annotated image
                               ↓
                    React Dashboard :5173
                    (display results + maps)
```

### Key Timing

- **Frame arrival → Depth arrival**: Must be within **300ms** (configurable) for fusion
- **Frame TTL**: Discarded after **2 seconds** if no depth arrives
- **Worker pool**: **4 goroutines** (configurable) forward fused payloads in parallel
- **Queue depth**: **64 slots** (configurable) before overflow drops frames

## Project Structure

```
profiler/
├── backend/                     # Flask ML server (Python)
│   ├── routes/
│   │   ├── detect.py           # POST /api/stream/frame (from relayer)
│   │   ├── logs.py             # Google Sheets integration
│   │   └── test.py
│   ├── utils/
│   │   ├── yolo_runner.py      # YOLOv8 inference (CUDA/CPU)
│   │   ├── material_estimator.py
│   │   └── sheets.py
│   ├── models/                 # Trained weights (.pt, .pkl)
│   ├── requirements.txt
│   └── app.py
│
├── sensor-relayer/              # Go relay service
│   ├── main.go
│   ├── internal/
│   │   ├── config/
│   │   ├── models/
│   │   ├── store/
│   │   ├── handler/
│   │   ├── worker/
│   │   └── server/
│   ├── web/
│   │   ├── static/
│   │   │   └── index.html      # Dashboard UI
│   │   └── embed.go
│   ├── README.md
│   ├── simulator.py            # Test tool
│   └── Dockerfile              # Multi-stage (10 MB final)
│
├── frontend/                        # React dashboard
│   ├── src/
│   ├── index.html
│   ├── package.json
│   ├── vite.config.js
│   └── eslint.config.js
│
├── docs/
│   ├── ABOUT.md                # Executive summary
│   └── ARCHITECTURE.MD         # Technical deep-dive
│
├── Makefile                    # Build/run commands
└── README.md                   # This file
```

## Hardware Design

### Components

| Item         | Model         | Cost         | Role                 |
| ------------ | ------------- | ------------ | -------------------- |
| RC Chassis   | Rock crawler  | ₹1,500–2,500 | Platform             |
| Camera       | ESP32-CAM     | ₹500–700     | Frame capture        |
| Depth Sensor | VL53L1X (ToF) | ₹500–800     | Distance measurement |
| Power        | 5V power bank | ₹500         | System power         |

### Wiring

- **ESP32-CAM** captures JPEG via built-in camera
- **VL53L1X** connected via I2C (SCL/SDA) to ESP32
- Both post to relayer via WiFi using HTTP

### Constraints

- Dark asphalt reduces depth sensor IR reflectance (MVP targets lighter pavement)
- Camera resolution: configurable (default 320×240)
- Depth range: 4mm–4000mm (±15mm accuracy typical)

## Configuration

### Backend (.env)

```bash
YOLO_WEIGHTS=models/pothole_crack_detector/best.pt
YOLO_CLASS_ID=0              # Class ID for potholes
YOLO_CONFIDENCE=0.3          # Detection threshold
SHEETS_CREDS=credentials.json
```

### Relayer (.env)

```bash
RELAYER_ADDR=:5001
BACKEND_URL=http://localhost:5000/api/stream/frame
FUSE_WINDOW=300ms            # Max frame-depth time delta
MAX_FRAME_AGE=2s             # Drop old frames
FORWARD_TIMEOUT=5s           # HTTP timeout
WORKER_COUNT=4               # Parallel forwarders
QUEUE_SIZE=64                # Queue buffer depth
PORT=5001                    # Override listen port (Railway)
```

### Frontend (.env)

```bash
VITE_API_URL=http://localhost:5000
```

## API Reference

### Relayer Endpoints (Port :5001)

| Method | Path         | Body                         | Response         |
| ------ | ------------ | ---------------------------- | ---------------- |
| POST   | /api/frame   | raw JPEG or multipart        | 204              |
| POST   | /api/depth   | `{"distance": 123.4}`        | 204              |
| POST   | /api/gps     | `{"lat": 28.6, "lng": 77.2}` | 204              |
| GET    | /api/metrics | —                            | JSON (counters)  |
| GET    | /            | —                            | HTML (dashboard) |
| GET    | /health      | —                            | 200 OK           |

### Backend Endpoints (Port :5000)

| Method | Path              | Body                | Response           |
| ------ | ----------------- | ------------------- | ------------------ |
| POST   | /api/stream/frame | multipart (relayer) | JSON + image       |
| GET    | /api/logs         | —                   | JSON (sheet rows)  |
| POST   | /api/test/sheets  | —                   | 200 (connectivity) |

## Development

### Build All

```bash
make build-relayer           # Go binary
```

### Run Dev Servers

```bash
make dev-server              # Python (port 5000)
make dev-relayer             # Go (port 5001)
make dev-frontend            # React (port 5173)
```

### Testing

```bash
make simulate-relayer        # Send fake sensor data
curl http://localhost:5001/api/metrics  # Check relayer stats
```

### Docker

```bash
cd sensor-relayer
docker build -t sensor-relayer:latest .
docker run -p 5001:5001 \
  -e BACKEND_URL=http://host.docker.internal:5000/api/stream/frame \
  sensor-relayer:latest
```

## Performance Metrics

### Relayer (Go)

- **Throughput**: ~1200 frames/sec on 4-worker pool
- **Latency**: <50ms frame-to-forward (P95)
- **Memory**: ~20 MB (frame buffer + workers)
- **CPU**: 2–3 cores per 1000 fps

### Backend (Python + YOLOv8)

#### CPU-Only (Baseline)

- **YOLOv8 inference**: ~450–550ms per frame (i7-12700K)
- **Material estimation**: 5–10ms (sklearn RandomForest)
- **Sheets write**: ~2–3s (async, non-blocking)
- **Throughput**: ~2 frames/second

#### GPU-Accelerated ⚡ (Recommended for Production)

- **YOLOv8 inference**: ~15–25ms per frame (RTX 3070)
- **Material estimation**: 5–10ms (sklearn RandomForest, CPU)
- **Sheets write**: ~2–3s (async, non-blocking)
- **Throughput**: ~15–20 frames/second
- **Speedup**: **20–30x faster than CPU**

_Note: GPU requires NVIDIA CUDA Toolkit 12.1+ and cuDNN 9.0+. Backend auto-detects GPU and falls back to CPU if unavailable. See [backend/README.md](backend/README.md) for GPU setup._

### End-to-End

- **Sensor capture → Dashboard display (GPU)**: ~500–800ms total
- **Detection accuracy**: 85–90% on trained dataset
- **Volume estimation error**: ±10–15% (calibrated on 18-sample dataset)

## Known Limitations

1. **Depth sensor**: IR reflectance issues on dark asphalt → upgrade to LiDAR for production
2. **Camera**: 320×240 default resolution → increase for finer defect details
3. **Material model**: Trained on 18 samples → collect more for robustness
4. **GPU availability**: Not all deployments have NVIDIA GPUs; backend gracefully falls back to CPU
5. **GPS**: Optional; not all deployments have location data
6. **Sheets latency**: Async writes can delay log updates by 2–5 seconds

## Future Work

- [ ] LiDAR upgrade for all-weather operation
- [ ] Edge ML (TensorFlow Lite on ESP32)
- [ ] Multi-robot coordination (fleet mode)
- [ ] LoRaWAN fallback for off-WiFi zones
- [ ] AR overlay for field crews
- [ ] Cost/material database expansion (>100 repair types)
- [ ] GPU optimization: batch inference, INT8 quantization

## Contributing

1. Fork the repo
2. Create a feature branch
3. Make your changes (follow the `.cursorrules` style guide)
4. Test: `make dev-server dev-relayer simulate-relayer`
5. Submit a PR

## Documentation

- **[ABOUT.md](docs/ABOUT.md)** — Executive summary, problem statement, objectives
- **[ARCHITECTURE.MD](docs/ARCHITECTURE.MD)** — Technical deep-dive (hardware, ML pipeline, data flow)
- **[sensor-relayer/README.md](sensor-relayer/README.md)** — Go relay service details
- **[backend/README.md](backend/README.md)** — Python Flask server & GPU setup guide
- **[frontend/README.md](frontend/README.md)** — React dashboard guide
