# Pavement Profiler -- Technical Architecture

> Automated Road Defect Detection & Volume Estimation System  
> MVP | Computer Vision + Sensor Fusion + ML Material Estimation + Data Pipeline

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Data Flow (ESP32 → Relayer → Backend)](#2-data-flow-esp32--relayer--backend)
3. [High-Level Architecture](#3-high-level-architecture)
4. [Sensor-Relayer (Go)](#4-sensor-relayer-go)
5. [Hardware Layer](#5-hardware-layer)
6. [Backend -- Flask ML Server](#6-backend--flask-ml-server)
7. [ML Pipeline -- YOLOv8 Inference](#7-ml-pipeline--yolov8-inference)
8. [Volume Estimation Model](#8-volume-estimation-model)
9. [Material & Cost Estimation](#9-material--cost-estimation)
10. [Data Pipeline -- Google Sheets](#10-data-pipeline--google-sheets)
11. [Frontend Dashboard](#11-frontend-dashboard)
12. [API Reference](#12-api-reference)
13. [Data Schema](#13-data-schema)
14. [Calibration & Error Budget](#14-calibration--error-budget)
15. [Tech Stack Summary](#15-tech-stack-summary)
16. [Known Limitations & Future Work](#16-known-limitations--future-work)

---

## 1. System Overview

The Pavement Profiler is a low-cost, automated road defect detection system designed to replace manual inspection workflows. It combines a ground-traversing robot with computer vision and laser depth sensing to produce objective, repeatable measurements of pothole geometry -- and pipes that data to a live dashboard.

**Core capability:** Given an image of a road surface and a ToF depth reading, the system returns:

- Detected potholes/cracks with bounding boxes and confidence scores
- Estimated pothole surface area (m2), maximum depth (m), repair volume (litres)
- Severity classification (LOW / MEDIUM / HIGH / CRITICAL)
- Material quantities (hot-mix asphalt, tack coat, aggregate base)
- Estimated repair cost (INR)
- Recommended repair method
- Geotagged data record in Google Sheets
- Annotated image with bounding box overlay

---

## 2. Data Flow (ESP32 → Relayer → Backend)

### Sequence Diagram

```
ESP32-CAM                Sensor-Relayer              Flask Backend
    |                          |                           |
    |--POST /api/frame-------->|                           |
    |   (JPEG binary)          |                           |
    |                    (buffers frame)                   |
    |                          |                           |
    |--POST /api/depth-------->|                           |
    |   (JSON: {distance})     |                           |
    |                    (fuses frame+depth)              |
    |                    (within 300ms window)             |
    |                          |                           |
    |                          |--POST /api/stream/frame-->|
    |                          |   (multipart: image,      |
    |                          |    depth_mm, lat, lng,    |
    |                          |    time_diff_ms)          |
    |                          |                           |
    |                          |<--204 No Content----------|
    |                          |                           |
    |--POST /api/gps---------->|                           |
    |   (JSON: lat/lng)   (stores latest)                  |
    |                          |                           |
```

### Key Timing Constraints

- **Frame arrival → Depth arrival**: Must be within `FUSE_WINDOW` (default 300ms) to create a fused payload
- **If depth doesn't arrive in time**: Frame is discarded after 2 seconds (configurable via `MAX_FRAME_AGE`)
- **Worker forwarding**: 4 parallel goroutines (configurable via `WORKER_COUNT`) forward to Python backend with 5s timeout per request
- **Queue overflow**: If fused payloads exceed `QUEUE_SIZE` (default 64), oldest is dropped with a warning

---

## 3. High-Level Architecture

```
+-----------------------------------------------------------+
|                      RC ROBOT UNIT                         |
|                                                            |
|   +--------------+       +-----------------------+         |
|   |  ESP32-CAM   |------>|    VL53L1X ToF Sensor |         |
|   |  (JPEG stream|       |    (depth in mm)      |         |
|   |   via Wi-Fi) |       +-----------------------+         |
|   +------+-------+                  |                      |
+----------+--------------------------+----------------------+
           |  HTTP POST /api/frame    |
           |  + /api/depth            |
           v                          v
+-----------------------------------------------------------+
|            SENSOR-RELAYER (Go) :5001                        |
|                                                            |
|   +------------------+    +-------------------+           |
|   | Frame/Depth/GPS  |    | Worker Pool       |           |
|   | Store (sync)     |--->| (fusion + forward)|           |
|   +------------------+    +-------------------+           |
|         ^                              |                  |
|         |                              v                  |
|   +------------------+    +-------------------+           |
|   | Fusion Logic     |    | HTTP Client       |           |
|   | (300ms window)   |    | (multipart upload)|           |
|   +------------------+    +-------------------+           |
|                                      |                    |
+--------------------------------------+---------------------+
                                       |
                    HTTP POST /api/stream/frame
                    (image + depth_mm + lat/lng)
                                       v
+-----------------------------------------------------------+
|                  FLASK BACKEND (Python) :5000              |
|                                                            |
|   +---------------+   +-------------------+   +---------+ |
|   | yolo_runner   |-->| material_estimator|-->| sheets  | |
|   | (YOLOv8 +     |   | - volume est.     |   | (gspread| |
|   |  CUDA/CPU)    |   | - severity class. |   |  API)   | |
|   +---------------+   | - materials (ML   |   +---------+ |
|                        |   or rule-based)  |       |      |
|                        | - cost estimation |       v      |
|                        +-------------------+  Google      |
|                                               Sheets      |
+-----------------------------------------------------------+
           |
           v
+-----------------------------------------------------------+
|                REACT DASHBOARD (Frontend)                   |
|                                                            |
|   +--------------+  +--------------+  +--------------+     |
|   | Image Upload |  | Leaflet Map  |  | Logs Table   |     |
|   | + Annotated  |  | (defect pins)|  | (all rows    |     |
|   |   Preview    |  +--------------+  |  from Sheet) |     |
|   | + Materials  |                    +--------------+     |
|   | + Severity   |                                         |
|   | + Cost       |                                         |
|   +--------------+                                         |
+-----------------------------------------------------------+
```

---

## 4. Sensor-Relayer (Go)

The relayer is a high-performance stateless service that:

1. **Ingests** JPEG frames, depth samples, and GPS coordinates from ESP32 over HTTP
2. **Fuses** frame + depth by timestamp (tolerance: 300ms)
3. **Forwards** fused payloads to the Flask backend as multipart/form-data
4. **Meters** ingress/egress with atomic counters (lock-free)
5. **Buffers** with configurable queue depth and worker pool

### Purpose

- **Decouples** sensor timing from ML inference — ESP32 can post frame and depth at slightly different times, relayer handles sync
- **Scales** frame capture rate — multiple ESP32s can POST to same relayer; it's stateless
- **Reduces** backend load — batching, compression, connection pooling handled by Go's efficient HTTP client
- **Enables** live dashboarding — metrics endpoint provides queue depth, throughput, error counts

### File Structure

```
sensor-relayer/
    main.go                      # Entry point
    go.mod
    Dockerfile                   # Multi-stage (10 MB final image)
    simulator.py                 # Test tool to simulate ESP32 sensors
    .env.example
    internal/
        config/
            config.go            # FromEnv() + defaults
        models/
            types.go             # SensorFrame, DepthSample, FusedPayload
        store/
            store.go             # State mgmt: SetFrame, TryFuse, GetLatestFrame
        metrics/
            metrics.go           # Snapshot() for live metrics
        handler/
            handlers.go          # HTTP endpoints (Frame, Depth, GPS, Metrics, etc)
        worker/
            forward.go           # Forward payload to backend (multipart)
            pool.go              # Worker pool management
        server/
            server.go            # HTTP server setup + routes
    web/
        embed.go                 # Embeds index.html at compile-time
        static/
            index.html           # Live dashboard UI
    pkg/
        utils/
            utils.go             # Utility functions
```

### Configuration (Environment)

```bash
RELAYER_ADDR=:5001                                 # Listen port
BACKEND_URL=http://localhost:5000/api/stream/frame # ML backend endpoint
FUSE_WINDOW=300ms                                  # Max frame-depth age diff
MAX_FRAME_AGE=2s                                   # Drop old frames
FORWARD_TIMEOUT=5s                                 # HTTP timeout to backend
WORKER_COUNT=4                                     # Parallel forwarder goroutines
QUEUE_SIZE=64                                      # Internal channel buffer
PORT=<auto for Railway>                            # Override RELAYER_ADDR
```

### API Endpoints

| Method | Path         | Body                         | Response | Purpose                       |
| ------ | ------------ | ---------------------------- | -------- | ----------------------------- |
| POST   | /api/frame   | raw JPEG or multipart image  | 204      | Ingest frame from ESP32-CAM   |
| POST   | /api/depth   | `{"distance": 123.4}`        | 204      | Ingest depth from VL53L1X     |
| POST   | /api/gps     | `{"lat": 28.6, "lng": 77.2}` | 204      | Ingest GPS coordinates        |
| GET    | /api/metrics | —                            | JSON     | Live counters + queue status  |
| GET    | /api/config  | —                            | JSON     | Fetch backend URL             |
| POST   | /api/config  | `{"backend_url": "..."}`     | 200      | Update backend URL live       |
| GET    | /api/preview | —                            | JPEG     | Latest frame (for debugging)  |
| GET    | /            | —                            | HTML     | Dashboard UI                  |
| GET    | /health      | —                            | 200 OK   | Health check (load balancers) |

### Metrics Endpoint (GET /api/metrics)

```json
{
    "frames_received": 1234,
    "depth_received": 1250,
    "gps_received": 456,
    "fuse_success": 1200,
    "fuse_miss": 34,
    "forward_success": 1198,
    "forward_error": 2,
    "queue_dropped": 0,
    "queue_len": 3,
    "queue_cap": 64
}
```

---

### Components

| Component                | Model                         | Role                               | Cost (INR)  |
| ------------------------ | ----------------------------- | ---------------------------------- | ----------- |
| RC Chassis               | Rock crawler (high clearance) | Platform traversal                 | 1,500-2,500 |
| Microcontroller + Camera | ESP32-CAM                     | Image capture + Wi-Fi transmission | 500-700     |
| Depth Sensor             | VL53L1X (ToF laser)           | Vertical depth measurement         | 500-800     |
| Power                    | 5V power bank                 | System power                       | 500         |

### ESP32-CAM

- Captures JPEG frames at configurable resolution
- Posts frame to `/api/frame` endpoint on relayer (raw binary or multipart)
- Connected to VL53L1X via I2C for depth readings
- Sends GPS updates to `/api/gps` when available

### VL53L1X Time-of-Flight Sensor

- Uses 940nm infrared laser to measure distance
- Range: 4mm - 4000mm; accuracy: +/-15mm typical
- Connected via I2C to ESP32-CAM (SCL/SDA pins)
- Samples continuously; depth reading posted to `/api/depth`

**Known limitation:** Dark/absorptive asphalt surfaces reduce IR reflectance. MVP calibration targets lighter pavement. Industrial LiDAR is the upgrade path.

---

## 6. Backend -- Flask ML Server

### File Structure

```
backend/
    app.py                  # App factory, blueprint registration, CORS, ML init
    requirements.txt
    .env / .env.example
    routes/
        detect.py           # POST /api/detect  (detection + estimation pipeline)
        logs.py             # GET  /api/logs    (fetch all sheet records)
        test.py             # POST /api/test/sheets (Sheets connectivity test)
    utils/
        yolo_runner.py      # YOLOv8 model loading + CUDA-aware inference
        material_estimator.py   # Volume, severity, materials, cost, ML integration
        sheets.py           # Google Sheets read/write via gspread
    training/
        __init__.py
        material_estimator_trainer.py   # Train sklearn models for material prediction
    models/
        pothole_crack_detector/
            pothole_crack_detector.pt   # Trained YOLOv8 weights
        material_estimator/
            material_hotmix_kg.pkl      # RandomForest model
            material_tack_coat_liters.pkl
            material_aggregate_base_kg.pkl
            scaler_hotmix_kg.pkl        # StandardScaler per target
            scaler_tack_coat_liters.pkl
            scaler_aggregate_base_kg.pkl
    data/
        sample_repair_data.csv      # 18 sample repair records for training
        repair_data_template.csv    # CSV template for data collection
```

### Two ML Models

| Model                  | Type                        | Purpose                                             | CUDA                    |
| ---------------------- | --------------------------- | --------------------------------------------------- | ----------------------- |
| Pothole/Crack Detector | YOLOv8 (.pt)                | Detect defects in images, produce bounding boxes    | Yes (auto)              |
| Material Estimator     | sklearn RandomForest (.pkl) | Predict material quantities from pothole dimensions | No (CPU-only by design) |

### Request Lifecycle -- `POST /api/stream/frame` (from Relayer)

**Note:** The endpoint is now called `/api/stream/frame` (not `/api/detect`) to accommodate the relayer's multipart format with fused depth and GPS.

```
1. Parse multipart form -> extract image bytes, depth_mm, lat, lng
2. yolo_runner.run_inference(image_bytes)
       Load/reuse cached YOLOv8 model (CUDA if available, else CPU)
       Run inference on numpy array
       Filter detections by confidence threshold (>0.3)
       Return list of {area_px, confidence, bbox, class_id} + annotated base64 image
3. Select largest detection (max area_px)
4. material_estimator.estimate_volume(area_px, depth_mm, confidence)
       area_px * PX_TO_MM^2 -> area_m2
       depth_mm -> depth_m
       volume = area_m2 * depth_m * 0.7
5. material_estimator.predict_materials_ml(area_m2, depth_m, volume_liters)
       If ML models loaded: sklearn predict -> {hotmix_kg, tack_coat_liters, aggregate_base_kg}
       Else: rule-based estimation with severity multipliers (fallback)
6. material_estimator.classify_severity(area_m2, depth_m) -> LOW/MEDIUM/HIGH/CRITICAL
7. material_estimator.estimate_cost(materials, severity) -> total INR
8. sheets.append_to_sheet(payload)   <- non-blocking, failure is soft
9. Return JSON payload + annotated image
```

### Blueprint Architecture

```python
app.py
    detect_bp  ->  /api/detect       (POST)
    logs_bp    ->  /api/logs         (GET)
    test_bp    ->  /api/test/sheets  (POST)
```

CORS is enabled globally to allow the React frontend (and ESP32) to call the API from different origins.

### CUDA / Device Selection

`yolo_runner.py` automatically selects CUDA when available:

```python
device = "cuda" if torch.cuda.is_available() else "cpu"
```

Device and GPU name are logged once on first inference. The material estimator uses scikit-learn which is CPU-only.

---

## 7. ML Pipeline -- YOLOv8 Inference

### Model

- **Framework:** Ultralytics YOLOv8 (`ultralytics` Python package)
- **Weights:** `models/pothole_crack_detector/pothole_crack_detector.pt` -- trained on pothole/crack dataset
- **Fallback:** Set `YOLO_WEIGHTS=yolov8n.pt` in `.env` to use COCO pretrained nano model for demo
- **Device:** CUDA (GPU) when available, CPU otherwise

### Inference Flow

```python
image_bytes -> PIL.Image -> numpy array
    |
model(img_array, device=device)     # YOLOv8 forward pass (CUDA/CPU)
    |
result.boxes                        # bounding boxes, class IDs, confidence scores
    |
filter conf > 0.3
    |
if custom weights: filter by YOLO_CLASS_ID
    |
extract area_px = (x2-x1) * (y2-y1) per box
    |
result.plot() -> annotated numpy array -> base64 JPEG
```

### Model Caching

The model is lazy-loaded on first request and held in memory via module-level `_model` and `_device` globals. Subsequent requests reuse the loaded model and cached device selection.

---

## 8. Volume Estimation Model

### Formula

```
V = A * Z_max * C_f
```

| Symbol  | Meaning                          | Unit          |
| ------- | -------------------------------- | ------------- |
| `A`     | Pothole surface area             | m2            |
| `Z_max` | Maximum depth from ToF sensor    | m             |
| `C_f`   | Geometry correction factor (0.7) | dimensionless |
| `V`     | Estimated repair volume          | m3            |

The correction factor `0.7` accounts for the bowl-shaped, sloped geometry of real potholes -- a perfect cylinder overestimates volume. This heuristic is consistent with civil engineering preliminary BoQ estimation practice.

### Pixel-to-Metric Calibration

```python
PX_TO_MM = 0.5   # mm per pixel at ~30cm camera mount height

area_mm2  = area_px * PX_TO_MM^2
area_m2   = area_mm2 / 1_000_000
```

**Calibration procedure:** Place an object of known size (e.g. A4 sheet, 297mm x 210mm) at camera mount height. Measure its pixel dimensions. Compute:

```
PX_TO_MM = known_dimension_mm / measured_pixels
```

Update `PX_TO_MM` in `utils/material_estimator.py` before deployment.

---

## 9. Material & Cost Estimation

### Severity Classification

Based on area and depth thresholds (per IRC guidelines):

| Severity | Depth    | Area      | Repair Method                     |
| -------- | -------- | --------- | --------------------------------- |
| LOW      | < 25mm   | < 0.05m2  | Surface patch / slurry seal       |
| MEDIUM   | < 50mm   | < 0.15m2  | Throw-and-roll patch              |
| HIGH     | < 100mm  | < 0.30m2  | Full-depth semi-permanent patch   |
| CRITICAL | >= 100mm | >= 0.30m2 | Full-depth patch with base repair |

### Material Estimation -- Dual Mode

**Rule-based (fallback):** Uses IRC 15:2017 reference constants and severity-based multipliers:

- HMA density: 2.4 kg/L
- Tack coat rate: 0.3 L/m2
- Aggregate density: 1600 kg/m3
- Severity multipliers adjust quantities by damage level

**ML-based (primary when trained):** sklearn RandomForest/GradientBoosting models predict:

- `hotmix_kg` -- hot-mix asphalt quantity
- `tack_coat_liters` -- bitumen emulsion quantity
- `aggregate_base_kg` -- granular base material quantity

Input features: `area_m2`, `depth_m`, `volume_liters`

### Training

```bash
cd backend
python -m training.material_estimator_trainer --test
python -m training.material_estimator_trainer --data data/sample_repair_data.csv --model gradient_boosting --test
```

Models are saved to `models/material_estimator/`. On app startup, `enable_ml_mode()` loads them. If unavailable, the system falls back to rule-based estimation transparently.

### Cost Estimation

Per-unit costs (INR, market rates):

| Material/Resource            | Rate           |
| ---------------------------- | -------------- |
| Hot-mix asphalt              | 7.0 INR/kg     |
| Tack coat (bitumen emulsion) | 60.0 INR/L     |
| Aggregate base               | 1.0 INR/kg     |
| Labour (base)                | 300 INR/repair |
| Equipment (base)             | 150 INR/repair |

Labour and equipment costs are scaled by severity multipliers.

---

## 10. Data Pipeline -- Google Sheets

### Architecture

```
Flask backend
    -> gspread client (google-auth service account)
        -> Google Sheets API v4
            -> Spreadsheet (shared with service account)
                -> Sheet1 -> auto-created headers on first run
```

### Sheet Schema

| Column             | Type   | Description                     |
| ------------------ | ------ | ------------------------------- |
| timestamp          | int    | Unix epoch                      |
| datetime           | string | Human-readable local time       |
| lat                | float  | GPS latitude                    |
| lng                | float  | GPS longitude                   |
| area_m2            | float  | Detected pothole area           |
| depth_m            | float  | ToF depth reading               |
| volume_m3          | float  | Estimated repair volume         |
| volume_liters      | float  | Volume in litres                |
| confidence         | float  | YOLO detection confidence (0-1) |
| severity           | string | LOW / MEDIUM / HIGH / CRITICAL  |
| estimated_cost_inr | float  | Total estimated repair cost     |

### Setup Steps

1. Google Cloud Console -> enable **Sheets API** + **Drive API**
2. Create **Service Account** -> download `credentials.json`
3. Share your Google Sheet with the service account email (Editor role)
4. Set environment variables:
    ```
    GOOGLE_SHEET_ID=<id from sheet URL>
    GOOGLE_CREDS_JSON=credentials.json
    ```

### Failure Handling

Sheets writes are wrapped in a `try/except` -- a Sheets API failure does **not** break the detection response. The error is surfaced as a `sheets_warning` field in the JSON response.

---

## 11. Frontend Dashboard

### Technology

- **Framework:** React (Vite + functional components + hooks)
- **Map:** Leaflet.js via `react-leaflet`
- **Icons:** `lucide-react`
- **Styling:** Global CSS with design tokens (CSS custom properties)
- **Font:** JetBrains Mono

### Layout

```
+----------------------------------------------------+
|  HEADER -- Logo | Status | API connectivity dot     |
+------------+--------------------------------------- +
|            |  DEFECT MAP (Leaflet)                   |
|  CONTROL   |  - OpenStreetMap tiles                  |
|  PANEL     |  - Amber glow pins per detection        |
|  (380px)   |  - Popup: depth, volume, confidence     |
|            +---------------------------------------- +
|  - Image   |  DETECTION LOG TABLE                    |
|    upload  |  - Reverse chronological                |
|  - Preview |  - Colour-coded confidence badges       |
|    (4:3)   |  - Volume highlighted in amber          |
|  - Depth   |  - Refresh button                       |
|  - GPS     +---------------------------------------- +
|  - Run btn |
|  - Stats   |
|  - Severity|
|    badge   |
|  - Repair  |
|    method  |
|  - Material|
|    cards   |
|  - Cost    |
|  - Session |
|    summary |
+------------+
```

### State Management

All state is managed with React `useState`. No external state library needed at MVP scale.

| State variable | Purpose                                      |
| -------------- | -------------------------------------------- |
| `logs`         | All rows fetched from `/api/logs`            |
| `latest`       | Most recent detection result                 |
| `imagePreview` | URL for selected image before inference      |
| `annotatedImg` | Base64 annotated image returned from backend |
| `depthMm`      | ToF depth input value                        |
| `lat`, `lng`   | GPS coordinates for this scan                |
| `loading`      | Spinner state during API call                |
| `apiOk`        | Connectivity status (polled on mount)        |

### Control Panel -- Detection Results

After a successful detection, the control panel displays:

1. **Annotated image** (4:3 aspect ratio) with ANNOTATED badge
2. **Detection stats** -- Area (m2), Depth (m), Volume (L), Confidence (%)
3. **Severity** -- color-coded badge (green=LOW, amber=MEDIUM, dim=HIGH, red=CRITICAL)
4. **Repair method** -- text description per severity
5. **Prediction source** -- ML_MODEL or RULE_BASED
6. **Materials required** -- Hot-Mix Asphalt (kg), Tack Coat (L), Aggregate Base (kg)
7. **Estimated cost** (INR)

---

## 12. API Reference

### `POST /api/detect`

Detect potholes in an image and estimate repair volume, materials, and cost.

**Request** -- `multipart/form-data`

| Field      | Type  | Required | Description                |
| ---------- | ----- | -------- | -------------------------- |
| `image`    | file  | Yes      | JPEG or PNG from ESP32-CAM |
| `depth_mm` | float | Yes      | ToF sensor reading in mm   |
| `lat`      | float | No       | GPS latitude (default 0)   |
| `lng`      | float | No       | GPS longitude (default 0)  |

Also accepts `application/json` with base64-encoded `image` field.

**Response 200 -- pothole detected**

```json
{
    "status": "pothole_detected",
    "timestamp": 1718000000,
    "lat": 12.9716,
    "lng": 77.5946,
    "area_m2": 0.0423,
    "depth_m": 0.08,
    "volume_m3": 0.00235,
    "volume_liters": 2.352,
    "volume_min_liters": 1.8816,
    "volume_max_liters": 2.8224,
    "confidence": 0.871,
    "severity": "MEDIUM",
    "repair_method": "Throw-and-roll patch",
    "materials": {
        "hotmix_kg": 1.2,
        "tack_coat_liters": 0.045,
        "aggregate_base_kg": 0.1
    },
    "estimated_cost_inr": 580.34,
    "prediction_source": "ML_MODEL",
    "annotated_image": "<base64 JPEG string>"
}
```

**Response 200 -- no detection**

```json
{
    "status": "no_pothole",
    "message": "No pothole detected"
}
```

**Response 500**

```json
{
    "error": "<exception message>"
}
```

---

### `GET /api/logs`

Fetch all detection records from Google Sheets.

**Response 200**

```json
{
    "status": "ok",
    "data": [
        {
            "timestamp": 1718000000,
            "datetime": "2024-06-10 14:32:00",
            "lat": 12.9716,
            "lng": 77.5946,
            "area_m2": 0.042,
            "depth_m": 0.08,
            "volume_m3": 0.00235,
            "volume_liters": 2.352,
            "confidence": 0.871,
            "severity": "MEDIUM",
            "estimated_cost_inr": 580.34
        }
    ]
}
```

---

### `POST /api/test/sheets`

Write a dummy row and read back to verify Google Sheets connectivity.

**Response 200**

```json
{
    "status": "ok",
    "written_row": { ... },
    "row_count": 14,
    "last_rows": [ ... ]
}
```

---

## 13. Data Schema

### Detection Record

```
Detection
    timestamp        : unix int
    datetime         : ISO string
    location
        lat          : float (WGS84)
        lng          : float (WGS84)
    geometry
        area_m2      : float
        depth_m      : float
        volume_m3    : float
        volume_liters: float
    ml_metadata
        confidence   : float (0-1)
        prediction_source : string (ML_MODEL | RULE_BASED)
    repair
        severity     : string (LOW | MEDIUM | HIGH | CRITICAL)
        repair_method: string
        materials
            hotmix_kg         : float
            tack_coat_liters  : float
            aggregate_base_kg : float
        estimated_cost_inr : float
```

---

## 14. Calibration & Error Budget

### Camera Calibration

```
Mount height: ~30cm above road surface
PX_TO_MM default: 0.5mm/px

Recalibrate by:
  1. Place A4 paper (297mm x 210mm) flat on road
  2. Capture image from mounted height
  3. Measure pixel width of paper in captured frame
  4. PX_TO_MM = 297 / measured_pixels
```

### ToF Sensor Notes

- Valid range: 4mm - 4,000mm
- Optimal for: light grey / beige asphalt
- Degraded by: wet surfaces, dark asphalt, steep angles >45 degrees
- Upgrade path: industrial LiDAR (e.g. RPLIDAR A1) or structured light scanner

### Volume Estimation Error

| Source                        | Expected Error           |
| ----------------------------- | ------------------------ |
| Volume estimation (heuristic) | +/-15%                   |
| ToF depth on dark asphalt     | +/-5-10mm                |
| Pixel-to-metric calibration   | +/-5% (post-calibration) |
| Total combined (RSS)          | ~+/-18%                  |

This is still superior to manual estimation which typically exceeds +/-20% wastage.

---

## 15. Tech Stack Summary

| Layer            | Technology                  | Rationale                                 |
| ---------------- | --------------------------- | ----------------------------------------- |
| Robot MCU        | ESP32-CAM                   | Low cost, Wi-Fi, camera integrated        |
| Depth Sensor     | VL53L1X                     | I2C, accurate at short range, cheap       |
| Backend          | Flask 3.1                   | Lightweight, quick to set up              |
| Object Detection | YOLOv8 (Ultralytics) + CUDA | Industry standard, GPU-accelerated        |
| Material Est. ML | scikit-learn (RandomForest) | Lightweight, fast training, no GPU needed |
| Volume Math      | Custom Python               | Straightforward formula, tweakable        |
| Data Storage     | Google Sheets               | Zero cost, accessible, no DB setup        |
| Sheets Client    | gspread + google-auth       | Official + well maintained                |
| Frontend         | React (Vite)                | Component model, easy state management    |
| Map              | Leaflet.js (react-leaflet)  | Free, OSM tiles, no API key needed        |
| Hosting (dev)    | localhost                   | Flask dev server + Vite dev server        |

---

## 16. Known Limitations & Future Work

### MVP Limitations

| Limitation                           | Impact                               | Mitigation                              |
| ------------------------------------ | ------------------------------------ | --------------------------------------- |
| Small training dataset (18 records)  | ML material predictions may be rough | Collect 50+ real repair records         |
| Single depth sample per frame        | Misses depth variance across defect  | Multi-sample sweep or LiDAR point cloud |
| No GPS on ESP32-CAM                  | Coordinates must be entered manually | Add NEO-6M GPS module (~400 INR)        |
| Dark asphalt degrades ToF            | Depth inaccuracy                     | Ambient light correction or LiDAR       |
| Google Sheets as DB                  | Not scalable beyond ~1000 rows       | Migrate to SQLite or Supabase           |
| No auth on API                       | Open endpoint                        | Add API key header for production       |
| sklearn material models are CPU-only | Not a bottleneck (ms-level latency)  | Acceptable for current scale            |

### Upgrade Path

```
MVP (current)
  |
Phase 2: GPS module + larger training dataset + retrained material models
  |
Phase 3: On-device inference (ESP32-S3 + TFLITE) + offline buffering
  |
Phase 4: Full PCI (Pavement Condition Index) scoring + automated routing
```

---

_Generated for internal project documentation -- Pavement Profiler MVP_
