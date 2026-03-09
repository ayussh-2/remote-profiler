# Pavement Profiler — Technical Architecture

> Automated Road Defect Detection & Volume Estimation System  
> MVP | Computer Vision + Sensor Fusion + Data Pipeline

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [High-Level Architecture](#2-high-level-architecture)
3. [Hardware Layer](#3-hardware-layer)
4. [Backend — Flask ML Server](#4-backend--flask-ml-server)
5. [ML Pipeline — YOLOv8 Inference](#5-ml-pipeline--yolov8-inference)
6. [Volume Estimation Model](#6-volume-estimation-model)
7. [Data Pipeline — Google Sheets](#7-data-pipeline--google-sheets)
8. [Frontend Dashboard](#8-frontend-dashboard)
9. [API Reference](#9-api-reference)
10. [Data Schema](#10-data-schema)
11. [Calibration & Error Budget](#11-calibration--error-budget)
12. [Tech Stack Summary](#12-tech-stack-summary)
13. [Known Limitations & Future Work](#13-known-limitations--future-work)

---

## 1. System Overview

The Pavement Profiler is a low-cost, automated road defect detection system designed to replace manual inspection workflows. It combines a ground-traversing robot with computer vision and laser depth sensing to produce objective, repeatable measurements of pothole geometry — and pipes that data to a live dashboard.

**Core capability:** Given an image of a road surface and a ToF depth reading, the system returns:

- Estimated pothole surface area (m²)
- Maximum depth (m)
- Estimated repair volume (litres)
- Geotagged data record in Google Sheets
- Annotated image with bounding box overlay

---

## 2. High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     RC ROBOT UNIT                        │
│                                                          │
│   ┌──────────────┐       ┌───────────────────────┐      │
│   │  ESP32-CAM   │──────▶│    VL53L1X ToF Sensor │      │
│   │  (JPEG stream│       │    (depth in mm)       │      │
│   │   via Wi-Fi) │       └───────────────────────┘      │
│   └──────┬───────┘                  │                    │
└──────────┼───────────────────────── ┼ ───────────────────┘
           │  HTTP multipart/form     │
           │  POST /api/detect        │
           ▼                          ▼
┌──────────────────────────────────────────────────────────┐
│                   FLASK BACKEND (Python)                  │
│                                                          │
│   ┌─────────────┐   ┌──────────────┐   ┌─────────────┐  │
│   │ yolo_runner │──▶│  estimator   │──▶│ sheets.py   │  │
│   │ (YOLOv8     │   │  (A×Z×0.7)  │   │ (gspread)   │  │
│   │  inference) │   │             │   │             │  │
│   └─────────────┘   └──────────────┘   └─────────────┘  │
│          │                                    │           │
│          ▼                                    ▼           │
│   annotated image                    Google Sheets        │
│   + JSON response                    (live log)          │
└──────────────────────────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────────────────────┐
│                REACT DASHBOARD (Frontend)                 │
│                                                          │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│   │  Image Upload│  │  Leaflet Map │  │  Logs Table  │  │
│   │  + Annotated │  │  (defect     │  │  (all rows   │  │
│   │    Preview   │  │   pins)      │  │   from Sheet)│  │
│   └──────────────┘  └──────────────┘  └──────────────┘  │
└──────────────────────────────────────────────────────────┘
```

---

## 3. Hardware Layer

### Components

| Component                | Model                         | Role                               | Cost (INR)  |
| ------------------------ | ----------------------------- | ---------------------------------- | ----------- |
| RC Chassis               | Rock crawler (high clearance) | Platform traversal                 | 1,500–2,500 |
| Microcontroller + Camera | ESP32-CAM                     | Image capture + Wi-Fi transmission | 500–700     |
| Depth Sensor             | VL53L1X (ToF laser)           | Vertical depth measurement         | 500–800     |
| Power                    | 5V power bank                 | System power                       | 500         |

### ESP32-CAM

- Captures JPEG frames at configurable resolution
- Streams or sends single frames via Wi-Fi to the Flask server using `HTTPClient`
- Posts to `POST /api/detect` as `multipart/form-data` alongside the ToF reading

### VL53L1X Time-of-Flight Sensor

- Uses 940nm infrared laser to measure distance
- Range: 4mm – 4000mm; accuracy: ±15mm typical
- Connected via I²C to ESP32-CAM (SCL/SDA pins)
- Samples continuously; peak depth over a defect is captured as `Z_max`

**Known limitation:** Dark/absorptive asphalt surfaces reduce IR reflectance. MVP calibration targets lighter pavement. Industrial LiDAR is the upgrade path.

---

## 4. Backend — Flask ML Server

### File Structure

```
backend/
├── app.py                  # App factory, blueprint registration, CORS
├── requirements.txt
├── .env.example
├── routes/
│   ├── detect.py           # POST /api/detect
│   └── logs.py             # GET  /api/logs
└── utils/
    ├── yolo_runner.py      # YOLOv8 model loading + inference
    ├── estimator.py        # Volume math
    └── sheets.py           # Google Sheets read/write via gspread
```

### Request Lifecycle — `POST /api/detect`

```
1. Parse multipart form → extract image bytes, depth_mm, lat, lng
2. yolo_runner.run_inference(image_bytes)
   └── Load/reuse cached YOLOv8 model
   └── Run inference on numpy array
   └── Filter detections by confidence threshold (>0.3)
   └── Return list of {area_px, confidence, bbox} + annotated base64 image
3. Select largest detection (max area_px)
4. estimator.estimate_volume(area_px, depth_mm, confidence)
   └── area_px × PX_TO_MM² → area_mm² → area_m²
   └── depth_mm → depth_m
   └── volume = area_m² × depth_m × 0.7
5. sheets.append_to_sheet(payload)  ← non-blocking, failure is soft
6. Return JSON payload + annotated image
```

### Blueprint Architecture

```python
app.py
├── detect_bp  →  /api/detect   (POST)
└── logs_bp    →  /api/logs     (GET)
```

CORS is enabled globally to allow the React frontend (and ESP32) to call the API from different origins.

---

## 5. ML Pipeline — YOLOv8 Inference

### Model

- **Framework:** Ultralytics YOLOv8 (`ultralytics` Python package)
- **MVP weights:** `yolov8n.pt` — nano model, COCO pretrained, downloads automatically
- **Production path:** Fine-tune on pothole dataset (e.g. Roboflow Universe pothole datasets) → set `YOLO_WEIGHTS=pothole_best.pt`

### Inference Flow

```python
image_bytes → PIL.Image → numpy array
    ↓
model(img_array)          # YOLOv8 forward pass
    ↓
result.boxes              # bounding boxes, class IDs, confidence scores
    ↓
filter conf > 0.3
    ↓
extract area_px = (x2-x1) × (y2-y1) per box
    ↓
result.plot() → annotated numpy array → base64 JPEG
```

### Model Caching

The model is lazy-loaded on first request and held in memory via a module-level `_model` global. Subsequent requests reuse the loaded model, avoiding the ~1–2s load penalty on every call.

### Why YOLOv8?

- Single-stage detector: fast enough for near-real-time inference on CPU
- Industry-standard; well-documented; Ultralytics provides one-command fine-tuning
- `yolov8n` (nano) runs on CPU; `yolov8s/m` for GPU-accelerated accuracy improvement

---

## 6. Volume Estimation Model

### Formula

```
V = A × Z_max × C_f
```

| Symbol  | Meaning                          | Unit          |
| ------- | -------------------------------- | ------------- |
| `A`     | Pothole surface area             | m²            |
| `Z_max` | Maximum depth from ToF sensor    | m             |
| `C_f`   | Geometry correction factor (0.7) | dimensionless |
| `V`     | Estimated repair volume          | m³            |

The correction factor `0.7` accounts for the bowl-shaped, sloped geometry of real potholes — a perfect cylinder overestimates volume. This heuristic is consistent with civil engineering preliminary BoQ (Bill of Quantities) estimation practice.

### Pixel-to-Metric Calibration

```python
PX_TO_MM = 0.5   # mm per pixel at ~30cm camera mount height

area_mm2  = area_px × PX_TO_MM²
area_m2   = area_mm2 / 1_000_000
```

**Calibration procedure:** Place an object of known size (e.g. an A4 sheet, 297mm × 210mm) at camera mount height. Measure its pixel dimensions. Compute:

```
PX_TO_MM = known_dimension_mm / measured_pixels
```

Update `PX_TO_MM` in `utils/estimator.py` before deployment.

### Error Budget

| Source                        | Expected Error         |
| ----------------------------- | ---------------------- |
| Volume estimation (heuristic) | ±15%                   |
| ToF depth on dark asphalt     | ±5–10mm                |
| Pixel-to-metric calibration   | ±5% (post-calibration) |
| Total combined (RSS)          | ~±18%                  |

This is still superior to manual estimation which typically exceeds **±20% wastage**.

---

## 7. Data Pipeline — Google Sheets

### Architecture

```
Flask backend
    └── gspread client (google-auth service account)
        └── Google Sheets API v4
            └── Spreadsheet (shared with service account)
                └── Sheet1 → auto-created headers on first run
```

### Sheet Schema

| Column        | Type   | Description                     |
| ------------- | ------ | ------------------------------- |
| timestamp     | int    | Unix epoch                      |
| datetime      | string | Human-readable local time       |
| lat           | float  | GPS latitude                    |
| lng           | float  | GPS longitude                   |
| area_m2       | float  | Detected pothole area           |
| depth_m       | float  | ToF depth reading               |
| volume_m3     | float  | Estimated repair volume         |
| volume_liters | float  | Volume in litres                |
| confidence    | float  | YOLO detection confidence (0–1) |

### Setup Steps

1. Google Cloud Console → enable **Sheets API** + **Drive API**
2. Create **Service Account** → download `credentials.json`
3. Share your Google Sheet with the service account email (Editor role)
4. Set environment variables:
    ```
    GOOGLE_SHEET_ID=<id from sheet URL>
    GOOGLE_CREDS_JSON=credentials.json
    ```

### Failure Handling

Sheets writes are wrapped in a `try/except` — a Sheets API failure does **not** break the detection response. The error is surfaced as a `sheets_warning` field in the JSON response.

---

## 8. Frontend Dashboard

### Technology

- **Framework:** React (functional components + hooks)
- **Map:** Leaflet.js loaded via CDN — no npm dependency needed
- **Styling:** Inline styles with a unified design token object (`C` for colors, `S` for style presets)
- **No build step required** — the `App.jsx` can run directly in any Vite/CRA project

### Layout

```
┌────────────────────────────────────────────────────┐
│  HEADER — Logo | Status | API connectivity dot      │
├────────────┬───────────────────────────────────────┤
│            │  DEFECT MAP (Leaflet)                  │
│  CONTROL   │  - OpenStreetMap tiles                 │
│  PANEL     │  - Amber glow pins per detection       │
│            │  - Popup: depth, volume, confidence    │
│  - Image   ├───────────────────────────────────────┤
│    upload  │  DETECTION LOG TABLE                   │
│  - Depth   │  - Reverse chronological              │
│    input   │  - Colour-coded confidence badges      │
│  - GPS     │  - Volume highlighted in amber         │
│  - Run btn │  - Refresh button                      │
│  - Stats   │                                        │
└────────────┴───────────────────────────────────────┘
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

### Map Integration

Leaflet is injected dynamically (CSS link + JS script) on component mount to avoid build-time dependency. Markers are re-rendered on `logs` state changes via a `useEffect`. The map centers on the last valid coordinate in the log.

---

## 9. API Reference

### `POST /api/detect`

Detect potholes in an image and estimate repair volume.

**Request** — `multipart/form-data`

| Field      | Type  | Required | Description                |
| ---------- | ----- | -------- | -------------------------- |
| `image`    | file  | ✅       | JPEG or PNG from ESP32-CAM |
| `depth_mm` | float | ✅       | ToF sensor reading in mm   |
| `lat`      | float | ❌       | GPS latitude (default 0)   |
| `lng`      | float | ❌       | GPS longitude (default 0)  |

**Response 200 — pothole detected**

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
    "confidence": 0.871,
    "annotated_image": "<base64 JPEG string>"
}
```

**Response 200 — no detection**

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
    "count": 14,
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
            "confidence": 0.871
        }
    ]
}
```

---

## 10. Data Schema

### Detection Record

```
Detection
├── timestamp       : unix int
├── datetime        : ISO string
├── location
│   ├── lat         : float (WGS84)
│   └── lng         : float (WGS84)
├── geometry
│   ├── area_m2     : float
│   ├── depth_m     : float
│   ├── volume_m3   : float
│   └── volume_liters: float
└── ml_metadata
    └── confidence  : float (0–1)
```

---

## 11. Calibration & Error Budget

### Camera Calibration

```
Mount height: ~30cm above road surface
PX_TO_MM default: 0.5mm/px

Recalibrate by:
  1. Place A4 paper (297mm × 210mm) flat on road
  2. Capture image from mounted height
  3. Measure pixel width of paper in captured frame
  4. PX_TO_MM = 297 / measured_pixels
```

### ToF Sensor Notes

- Valid range: 4mm – 4,000mm
- Optimal for: light grey / beige asphalt
- Degraded by: wet surfaces, dark asphalt, steep angles >45°
- Upgrade path: industrial LiDAR (e.g. RPLIDAR A1) or structured light scanner

### Volume Estimation Error

```
Expected accuracy: ±15%  (heuristic correction factor)
Benchmark: Manual estimation wastage typically ±20%
Net improvement: ~5% reduction in material estimation error
```

---

## 12. Tech Stack Summary

| Layer           | Technology            | Rationale                              |
| --------------- | --------------------- | -------------------------------------- |
| Robot MCU       | ESP32-CAM             | Low cost, Wi-Fi, camera integrated     |
| Depth Sensor    | VL53L1X               | I²C, accurate at short range, cheap    |
| Backend         | Flask 3.0             | Lightweight, quick to set up           |
| Computer Vision | YOLOv8 (Ultralytics)  | Industry standard, CPU-feasible        |
| Volume Math     | Custom Python         | Straightforward formula, tweakable     |
| Data Storage    | Google Sheets         | Zero cost, accessible, no DB setup     |
| Sheets Client   | gspread + google-auth | Official + well maintained             |
| Frontend        | React (JSX)           | Component model, easy state management |
| Map             | Leaflet.js            | Free, OSM tiles, no API key needed     |
| Hosting (dev)   | localhost             | Flask dev server + Vite dev server     |

---

## 13. Known Limitations & Future Work

### MVP Limitations

| Limitation                                     | Impact                               | Mitigation                              |
| ---------------------------------------------- | ------------------------------------ | --------------------------------------- |
| Pretrained COCO weights (not pothole-specific) | Lower detection accuracy             | Fine-tune on Roboflow pothole dataset   |
| Single depth sample per frame                  | Misses depth variance across defect  | Multi-sample sweep or LiDAR point cloud |
| No GPS on ESP32-CAM                            | Coordinates must be entered manually | Add NEO-6M GPS module (~₹400)           |
| Dark asphalt degrades ToF                      | Depth inaccuracy                     | Ambient light correction or LiDAR       |
| Google Sheets as DB                            | Not scalable beyond ~1000 rows       | Migrate to SQLite or Supabase           |
| No auth on API                                 | Open endpoint                        | Add API key header for production       |

### Upgrade Path

```
MVP (this week)
  ↓
Phase 2: Fine-tuned pothole YOLO model + GPS module
  ↓
Phase 3: On-device inference (ESP32-S3 + TFLITE) + offline buffering
  ↓
Phase 4: Full PCI (Pavement Condition Index) scoring + automated routing
```

---

_Generated for internal project documentation — Pavement Profiler MVP_
