# Pavement Profiler -- Technical Architecture

> Automated Road Defect Detection & Volume Estimation System  
> MVP | Computer Vision + Sensor Fusion + ML Material Estimation + Data Pipeline

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [High-Level Architecture](#2-high-level-architecture)
3. [Hardware Layer](#3-hardware-layer)
4. [Backend -- Flask ML Server](#4-backend--flask-ml-server)
5. [ML Pipeline -- YOLOv8 Inference](#5-ml-pipeline--yolov8-inference)
6. [Volume Estimation Model](#6-volume-estimation-model)
7. [Material & Cost Estimation](#7-material--cost-estimation)
8. [Data Pipeline -- Google Sheets](#8-data-pipeline--google-sheets)
9. [Frontend Dashboard](#9-frontend-dashboard)
10. [API Reference](#10-api-reference)
11. [Data Schema](#11-data-schema)
12. [Calibration & Error Budget](#12-calibration--error-budget)
13. [Tech Stack Summary](#13-tech-stack-summary)
14. [Known Limitations & Future Work](#14-known-limitations--future-work)

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

## 2. High-Level Architecture

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
           |  HTTP multipart/form     |
           |  POST /api/detect        |
           v                          v
+-----------------------------------------------------------+
|                   FLASK BACKEND (Python)                    |
|                                                            |
|   +---------------+   +-------------------+   +---------+  |
|   | yolo_runner   |-->| material_estimator|-->| sheets  |  |
|   | (YOLOv8 +     |   | - volume est.     |   | (gspread|  |
|   |  CUDA/CPU)    |   | - severity class. |   |  API)   |  |
|   +---------------+   | - materials (ML   |   +---------+  |
|                        |   or rule-based)  |       |        |
|                        | - cost estimation |       v        |
|                        +-------------------+  Google Sheets |
|                                                (live log)   |
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

## 3. Hardware Layer

### Components

| Component                | Model                         | Role                               | Cost (INR)  |
| ------------------------ | ----------------------------- | ---------------------------------- | ----------- |
| RC Chassis               | Rock crawler (high clearance) | Platform traversal                 | 1,500-2,500 |
| Microcontroller + Camera | ESP32-CAM                     | Image capture + Wi-Fi transmission | 500-700     |
| Depth Sensor             | VL53L1X (ToF laser)           | Vertical depth measurement         | 500-800     |
| Power                    | 5V power bank                 | System power                       | 500         |

### ESP32-CAM

- Captures JPEG frames at configurable resolution
- Streams or sends single frames via Wi-Fi to the Flask server using `HTTPClient`
- Posts to `POST /api/detect` as `multipart/form-data` alongside the ToF reading

### VL53L1X Time-of-Flight Sensor

- Uses 940nm infrared laser to measure distance
- Range: 4mm - 4000mm; accuracy: +/-15mm typical
- Connected via I2C to ESP32-CAM (SCL/SDA pins)
- Samples continuously; peak depth over a defect is captured as `Z_max`

**Known limitation:** Dark/absorptive asphalt surfaces reduce IR reflectance. MVP calibration targets lighter pavement. Industrial LiDAR is the upgrade path.

---

## 4. Backend -- Flask ML Server

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

| Model | Type | Purpose | CUDA |
| --- | --- | --- | --- |
| Pothole/Crack Detector | YOLOv8 (.pt) | Detect defects in images, produce bounding boxes | Yes (auto) |
| Material Estimator | sklearn RandomForest (.pkl) | Predict material quantities from pothole dimensions | No (CPU-only by design) |

### Request Lifecycle -- `POST /api/detect`

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

## 5. ML Pipeline -- YOLOv8 Inference

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

## 6. Volume Estimation Model

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

## 7. Material & Cost Estimation

### Severity Classification

Based on area and depth thresholds (per IRC guidelines):

| Severity | Depth      | Area      | Repair Method                      |
| -------- | ---------- | --------- | ---------------------------------- |
| LOW      | < 25mm     | < 0.05m2  | Surface patch / slurry seal        |
| MEDIUM   | < 50mm     | < 0.15m2  | Throw-and-roll patch               |
| HIGH     | < 100mm    | < 0.30m2  | Full-depth semi-permanent patch    |
| CRITICAL | >= 100mm   | >= 0.30m2 | Full-depth patch with base repair  |

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

| Material/Resource | Rate |
| --- | --- |
| Hot-mix asphalt | 7.0 INR/kg |
| Tack coat (bitumen emulsion) | 60.0 INR/L |
| Aggregate base | 1.0 INR/kg |
| Labour (base) | 300 INR/repair |
| Equipment (base) | 150 INR/repair |

Labour and equipment costs are scaled by severity multipliers.

---

## 8. Data Pipeline -- Google Sheets

### Architecture

```
Flask backend
    -> gspread client (google-auth service account)
        -> Google Sheets API v4
            -> Spreadsheet (shared with service account)
                -> Sheet1 -> auto-created headers on first run
```

### Sheet Schema

| Column            | Type   | Description                     |
| ----------------- | ------ | ------------------------------- |
| timestamp         | int    | Unix epoch                      |
| datetime          | string | Human-readable local time       |
| lat               | float  | GPS latitude                    |
| lng               | float  | GPS longitude                   |
| area_m2           | float  | Detected pothole area           |
| depth_m           | float  | ToF depth reading               |
| volume_m3         | float  | Estimated repair volume         |
| volume_liters     | float  | Volume in litres                |
| confidence        | float  | YOLO detection confidence (0-1) |
| severity          | string | LOW / MEDIUM / HIGH / CRITICAL  |
| estimated_cost_inr| float  | Total estimated repair cost     |

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

## 9. Frontend Dashboard

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

## 10. API Reference

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

## 11. Data Schema

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

## 12. Calibration & Error Budget

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

| Source                        | Expected Error         |
| ----------------------------- | ---------------------- |
| Volume estimation (heuristic) | +/-15%                 |
| ToF depth on dark asphalt     | +/-5-10mm              |
| Pixel-to-metric calibration   | +/-5% (post-calibration) |
| Total combined (RSS)          | ~+/-18%                |

This is still superior to manual estimation which typically exceeds +/-20% wastage.

---

## 13. Tech Stack Summary

| Layer             | Technology                      | Rationale                              |
| ----------------- | ------------------------------- | -------------------------------------- |
| Robot MCU         | ESP32-CAM                       | Low cost, Wi-Fi, camera integrated     |
| Depth Sensor      | VL53L1X                         | I2C, accurate at short range, cheap    |
| Backend           | Flask 3.1                       | Lightweight, quick to set up           |
| Object Detection  | YOLOv8 (Ultralytics) + CUDA    | Industry standard, GPU-accelerated     |
| Material Est. ML  | scikit-learn (RandomForest)     | Lightweight, fast training, no GPU needed |
| Volume Math       | Custom Python                   | Straightforward formula, tweakable     |
| Data Storage      | Google Sheets                   | Zero cost, accessible, no DB setup     |
| Sheets Client     | gspread + google-auth           | Official + well maintained             |
| Frontend          | React (Vite)                    | Component model, easy state management |
| Map               | Leaflet.js (react-leaflet)      | Free, OSM tiles, no API key needed     |
| Hosting (dev)     | localhost                       | Flask dev server + Vite dev server     |

---

## 14. Known Limitations & Future Work

### MVP Limitations

| Limitation                                     | Impact                               | Mitigation                              |
| ---------------------------------------------- | ------------------------------------ | --------------------------------------- |
| Small training dataset (18 records)            | ML material predictions may be rough | Collect 50+ real repair records         |
| Single depth sample per frame                  | Misses depth variance across defect  | Multi-sample sweep or LiDAR point cloud |
| No GPS on ESP32-CAM                            | Coordinates must be entered manually | Add NEO-6M GPS module (~400 INR)        |
| Dark asphalt degrades ToF                      | Depth inaccuracy                     | Ambient light correction or LiDAR       |
| Google Sheets as DB                            | Not scalable beyond ~1000 rows       | Migrate to SQLite or Supabase           |
| No auth on API                                 | Open endpoint                        | Add API key header for production       |
| sklearn material models are CPU-only           | Not a bottleneck (ms-level latency)  | Acceptable for current scale            |

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
