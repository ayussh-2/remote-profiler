# Pavement Profiler

## Automated Road Defect Detection & Volume Estimation System

**Project Documentation — MVP Release**

---

> _A low-cost, sensor-fused road assessment robot that replaces subjective manual inspection with objective, repeatable, geotagged engineering data._

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Problem Statement](#2-problem-statement)
3. [Project Objectives](#3-project-objectives)
4. [System Architecture](#4-system-architecture)
5. [Hardware Design](#5-hardware-design)
6. [Machine Learning Pipeline](#6-machine-learning-pipeline)
7. [Volume Estimation Model](#7-volume-estimation-model)
8. [Backend — Flask API Server](#8-backend--flask-api-server)
9. [Data Layer — Google Sheets](#9-data-layer--google-sheets)
10. [Frontend Dashboard](#10-frontend-dashboard)
11. [API Reference](#11-api-reference)
12. [Cost Analysis](#12-cost-analysis)
13. [Development Roadmap](#13-development-roadmap)
14. [Known Limitations & Mitigations](#14-known-limitations--mitigations)
15. [Future Work & Upgrade Path](#15-future-work--upgrade-path)
16. [Conclusion](#16-conclusion)

---

## 1. Executive Summary

The Pavement Profiler is a proof-of-concept infrastructure system that modernizes road condition assessment through low-cost automation, computer vision, and laser depth sensing. It replaces subjective manual inspection with objective, repeatable, geotagged measurements of road surface defects.

The system consists of two integrated components:

| Component                  | Description                                                                                                                                                                                                         |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **The Profiler Bot**       | A ground-traversing RC robot equipped with an ESP32-CAM and VL53L1X Time-of-Flight laser sensor. It captures road surface imagery and depth readings, transmitting structured data to the backend over Wi-Fi.       |
| **Transparency Dashboard** | A React-based web dashboard that receives detection results, displays annotated images, maps geotagged defects using Leaflet.js, logs all records to Google Sheets, and presents aggregate statistics to operators. |

The MVP targets three measurable improvements over the status quo: reduction in asphalt material wastage through accurate volume estimation, reduction in worker exposure to live traffic during manual surveys, and creation of a verifiable, auditable data trail for road maintenance operations.

---

## 2. Problem Statement

Current road maintenance workflows suffer from three systemic inefficiencies that compound over time.

### 2.1 Material Wastage (Cost Inefficiency)

Manual pothole repair relies on visual estimation of asphalt quantity by on-site engineers. This practice introduces significant subjective error — typically resulting in **10–20% material wastage** per repair, either through excess ordering that cannot be reused, or through underestimation that necessitates costly rework after premature patch failure.

> **Quantified impact:** A municipality performing 500 pothole repairs per year with an average asphalt cost of ₹800 per repair wastes ₹80,000–₹160,000 annually through poor estimation alone.

### 2.2 Survey Latency (Time Inefficiency)

Manual road inspection is slow, labour-intensive, and exposes survey workers to live traffic hazards. Because surveys are expensive, they are conducted infrequently — typically quarterly or after monsoon seasons. This delay allows minor surface defects (hairline cracks, shallow depressions) to propagate into larger structural failures, dramatically increasing repair costs and road closure durations.

> **Key risk:** A 20mm deep crack left unattended for one monsoon season can become a 120mm pothole requiring 6x the material and subbase repair.

### 2.3 Accountability Gap (Data Visibility)

Citizen complaints and internal reports about road defects lack verifiable, geotagged, quantitative engineering data. Without standardized measurements, road maintenance authorities cannot effectively:

- Prioritize repairs by severity
- Track response timelines
- Audit contractor work quality
- Demonstrate accountability to the public

---

## 3. Project Objectives

The Pavement Profiler MVP is designed to achieve the following primary objectives:

1. Automate the detection and classification of road surface defects using computer vision
2. Measure pothole depth objectively using laser time-of-flight sensing
3. Estimate repair material volume with repeatability superior to manual methods (target error: **<15%**)
4. Geotag each defect record for mapping and spatial analysis
5. Log all detections to a persistent, queryable data store (Google Sheets) in real time
6. Visualize the detection dataset on a live web dashboard accessible to operations staff
7. Demonstrate the technical and economic feasibility of low-cost automated road surveys

---

## 4. System Architecture

### 4.1 Architecture Overview

The system is organized into four distinct layers communicating over standard HTTP and I2C interfaces:

| Layer            | Components                     | Responsibility                 | Protocol              |
| ---------------- | ------------------------------ | ------------------------------ | --------------------- |
| **Hardware**     | ESP32-CAM, VL53L1X, RC Chassis | Physical sensing and mobility  | I2C, Wi-Fi (HTTP)     |
| **ML Backend**   | Flask, YOLOv8, Python          | Inference, estimation, routing | REST API (JSON)       |
| **Data Layer**   | Google Sheets, gspread         | Persistent storage and logging | Sheets API v4 (HTTPS) |
| **Presentation** | React, Leaflet.js              | Visualization and operator UI  | REST (fetch), CDN     |

### 4.2 System Diagram

```
┌────────────────────────────────────────────────────────────┐
│                       RC ROBOT UNIT                         │
│                                                            │
│   ┌───────────────┐          ┌──────────────────────┐     │
│   │  ESP32-CAM    │──I2C────▶│  VL53L1X ToF Sensor  │     │
│   │  OV2640 2MP   │          │  depth reading (mm)  │     │
│   │  Wi-Fi 802.11 │          └──────────────────────┘     │
│   └──────┬────────┘                                        │
└──────────┼─────────────────────────────────────────────────┘
           │ HTTP multipart/form-data
           │ POST /api/detect
           ▼
┌────────────────────────────────────────────────────────────┐
│                  FLASK BACKEND  (Python)                    │
│                                                            │
│  ┌──────────────┐   ┌──────────────┐   ┌───────────────┐  │
│  │ yolo_runner  │──▶│  estimator   │──▶│   sheets.py   │  │
│  │ (YOLOv8      │   │  V=A×Z×0.7   │   │   (gspread)   │  │
│  │  inference)  │   │              │   │               │  │
│  └──────────────┘   └──────────────┘   └───────┬───────┘  │
│         │                                       │          │
│         ▼                                       ▼          │
│   annotated image                       Google Sheets      │
│   + JSON response                       (live log)         │
└──────────────────────────────────────────────────────────┬─┘
                                                           │
                                                           ▼
┌────────────────────────────────────────────────────────────┐
│                REACT DASHBOARD  (Frontend)                  │
│                                                            │
│  ┌─────────────┐   ┌──────────────┐   ┌───────────────┐   │
│  │ Image Upload │   │ Leaflet Map  │   │  Logs Table   │   │
│  │ + Annotated │   │ defect pins  │   │  all records  │   │
│  │   Preview   │   │ with popups  │   │  from Sheet   │   │
│  └─────────────┘   └──────────────┘   └───────────────┘   │
└────────────────────────────────────────────────────────────┘
```

### 4.3 End-to-End Data Flow

For a single defect detection event:

1. The RC robot traverses a road segment with camera and ToF sensor active
2. The ESP32-CAM captures a JPEG frame; the VL53L1X records peak depth (Z_max) over the defect
3. The ESP32 sends a multipart HTTP POST to the Flask backend — image, depth_mm, lat, lng
4. Flask runs YOLOv8 inference on the image to detect potholes and extract bounding box pixel area
5. The volume estimator converts pixel area → metric area via calibration constant, then computes `V = A × Z × 0.7`
6. The result is appended to Google Sheets and returned as JSON with an annotated image (base64)
7. The React dashboard polls `GET /api/logs` and renders the updated map pins and log table

---

## 5. Hardware Design

### 5.1 Component Specifications

| Component                | Model              | Key Specs                               | Role                                       | Cost (INR)    |
| ------------------------ | ------------------ | --------------------------------------- | ------------------------------------------ | ------------- |
| RC Chassis               | Rock Crawler (4WD) | High ground clearance                   | Platform traversal over uneven surfaces    | ₹1,500–₹2,500 |
| Microcontroller + Camera | ESP32-CAM          | OV2640 2MP, 802.11 b/g/n Wi-Fi, 5V      | Image capture + wireless HTTP transmission | ₹500–₹700     |
| Depth Sensor             | VL53L1X            | 940nm laser, I2C, 4–4000mm range, ±15mm | Vertical depth measurement                 | ₹500–₹800     |
| Power Supply             | 5V USB Power Bank  | 5V / 2A output                          | Powers ESP32 and sensor                    | ₹500          |

### 5.2 ESP32-CAM

The ESP32-CAM integrates an Espressif ESP32-S microcontroller with an OV2640 2-megapixel camera and built-in 802.11 b/g/n Wi-Fi. For the MVP it captures JPEG images on demand and transmits them over Wi-Fi to the Flask server using the Arduino `HTTPClient` library. The module operates from a 5V supply and draws approximately 180–250mA during active transmission.

The camera is mounted facing **downward at approximately 30cm above the road surface** — a height that balances field-of-view coverage and spatial resolution for defect sizing.

**ESP32 → Flask transmission sketch (pseudocode):**

```cpp
// After capturing frame + reading ToF:
HTTPClient http;
http.begin("http://<server-ip>:5000/api/detect");
// Build multipart body: image JPEG + depth_mm + lat + lng
http.POST(multipart_body);
```

### 5.3 VL53L1X Time-of-Flight Sensor

The VL53L1X uses a 940nm VCSEL (Vertical Cavity Surface Emitting Laser) and SPAD (Single Photon Avalanche Diode) array to measure distance by timing the round-trip flight of laser pulses. It communicates with the ESP32 via I2C (SDA/SCL) and returns distance in millimetres.

| Property          | Value                                     |
| ----------------- | ----------------------------------------- |
| Measurement range | 4mm – 4,000mm                             |
| Typical accuracy  | ±15mm on reflective surfaces              |
| Interface         | I2C (up to 400kHz fast mode)              |
| Operating voltage | 2.6V – 3.5V (breakout board: 5V tolerant) |
| Laser wavelength  | 940nm (near-infrared, eye-safe Class 1)   |

> **Known limitation:** Dark/absorptive asphalt reduces IR reflectance, increasing depth measurement noise. MVP calibration targets lighter pavement. Industrial LiDAR (e.g. RPLIDAR A1) is the production upgrade path.

### 5.4 Physical Mounting

The sensor suite is mounted on a 3D-printed or laser-cut platform attached to the RC chassis. The ESP32-CAM is aimed vertically downward at the road surface. The VL53L1X is co-located adjacent to the camera, ensuring the depth sample is acquired at the same ground position as the image frame.

---

## 6. Machine Learning Pipeline

### 6.1 Object Detection — YOLOv8

The system uses **YOLOv8** (You Only Look Once, version 8) from Ultralytics for pothole detection. YOLO is a single-stage, anchor-free object detection framework that performs classification and bounding box regression in a single neural network forward pass, making it well-suited for near-real-time inference on CPU hardware.

| Attribute            | Detail                                                                  |
| -------------------- | ----------------------------------------------------------------------- |
| Framework            | Ultralytics YOLOv8 (`ultralytics` Python package)                       |
| MVP Weights          | `yolov8n.pt` — COCO pretrained nano model, auto-downloaded on first run |
| Production Weights   | Fine-tuned on pothole dataset (Roboflow Universe)                       |
| Input format         | RGB numpy array (PIL Image → np.array)                                  |
| Output               | List of bounding boxes: class ID, confidence score, xyxy coordinates    |
| Confidence threshold | 0.30 — detections below this are discarded                              |
| Model caching        | Lazy-loaded on first request; held in module-level global (`_model`)    |

### 6.2 Inference Pipeline

```
image bytes (JPEG)
    │
    ▼
PIL.Image.open() → RGB → numpy array
    │
    ▼
model(img_array, verbose=False)        ← YOLOv8 forward pass
    │
    ▼
result.boxes                           ← all detected bounding boxes
    │
    ├── filter: confidence > 0.30
    │
    ├── extract: area_px = (x2-x1) × (y2-y1) per box
    │
    └── select: largest area_px  →  primary pothole detection
    │
    ▼
result.plot()                          ← annotated numpy array
    │
    ▼
PIL → JPEG → base64 string             ← returned to frontend
```

### 6.3 Why YOLOv8?

YOLOv8 was selected for three reasons. It is fast enough for near-real-time inference on CPU (yolov8n runs at 30–80ms per image on modern laptop hardware), it is the current industry standard for embedded and edge deployment, and Ultralytics provides a clean one-command fine-tuning interface that makes domain adaptation straightforward.

### 6.4 Fine-Tuning Roadmap

For production deployment, the pretrained COCO model should be replaced with weights fine-tuned on pothole imagery:

1. Source labelled dataset from [Roboflow Universe](https://universe.roboflow.com/search?q=pothole) — choose a dataset with YOLO-format annotations
2. Augment with locally collected ESP32-CAM images of Indian road surfaces for domain adaptation
3. Fine-tune using the Ultralytics CLI:
    ```bash
    yolo train model=yolov8n.pt data=pothole.yaml epochs=50 imgsz=640
    ```
4. Evaluate on held-out test set — target **mAP50 > 0.75** before deployment
5. Set `YOLO_WEIGHTS=runs/detect/train/weights/best.pt` in `.env`

---

## 7. Volume Estimation Model

### 7.1 Mathematical Formula

The volume of repair material required for a pothole is estimated using a modified cylindrical model with a geometry correction factor:

```
V  =  A  ×  Z_max  ×  C_f
```

| Symbol  | Variable          | Unit                | Description                                       |
| ------- | ----------------- | ------------------- | ------------------------------------------------- |
| `V`     | Volume            | m³ / litres         | Estimated repair material volume                  |
| `A`     | Surface Area      | m²                  | Pothole surface area from YOLO bounding box       |
| `Z_max` | Maximum Depth     | m                   | Peak depth from VL53L1X ToF sensor                |
| `C_f`   | Correction Factor | 0.7 (dimensionless) | Accounts for bowl-shaped, sloped pothole geometry |

The correction factor `C_f = 0.7` heuristically accounts for the fact that real potholes are not perfect cylinders — they have sloped, bowl-shaped walls that reduce actual volume versus a cylindrical approximation. This value is consistent with civil engineering preliminary Bill of Quantities (BoQ) estimation practice.

### 7.2 Pixel-to-Metric Calibration

The YOLO bounding box is expressed in pixels. Converting to metric area requires a calibration constant `PX_TO_MM` (millimetres per pixel at camera mount height):

```python
# In utils/estimator.py
PX_TO_MM = 0.5          # mm per pixel at ~30cm camera height

area_mm2 = area_px  × (PX_TO_MM ** 2)
area_m2  = area_mm2 / 1_000_000
depth_m  = depth_mm / 1000

volume_m3     = area_m2 × depth_m × 0.7
volume_liters = volume_m3 × 1000
```

**Calibration procedure:**

1. Place an object of known size (e.g. an A4 sheet, 297mm × 210mm) flat on the road at camera mount height
2. Capture an image from the mounted camera
3. Measure the object's pixel width in the captured frame
4. Compute: `PX_TO_MM = 297 / measured_pixel_width`
5. Update `PX_TO_MM` in `utils/estimator.py` before deployment

### 7.3 Error Budget

| Error Source                 | Expected Magnitude     | Mitigation                                                   |
| ---------------------------- | ---------------------- | ------------------------------------------------------------ |
| Volume heuristic (C_f = 0.7) | ±15%                   | Accept as design constraint; still beats manual ±20% wastage |
| ToF on dark asphalt          | ±5–10mm                | Surface-specific calibration; LiDAR for production           |
| Pixel-metric calibration     | ±5% (post-calibration) | Re-calibrate per deployment unit                             |
| YOLO bounding box accuracy   | ±8–12%                 | Fine-tune on domain-specific data                            |
| **Combined (RSS estimate)**  | **~±18–20%**           | **Meets or beats manual estimation**                         |

> **Benchmark:** Manual estimation wastage in current workflows typically exceeds **±20%**. The Pavement Profiler meets or exceeds this bar even at MVP accuracy levels.

---

## 8. Backend — Flask API Server

### 8.1 File Structure

```
backend/
├── app.py                  # App factory, Blueprint registration, CORS
├── requirements.txt
├── .env.example
├── routes/
│   ├── detect.py           # POST /api/detect  ← primary endpoint
│   └── logs.py             # GET  /api/logs
└── utils/
    ├── yolo_runner.py      # YOLOv8 model loading + inference wrapper
    ├── estimator.py        # Volume calculation (A × Z × 0.7)
    └── sheets.py           # Google Sheets read/write via gspread
```

### 8.2 Application Structure

The backend uses Flask's **Blueprint** pattern for route registration, keeping concerns separated and making it easy to add new endpoints without touching the app factory.

```python
# app.py
app = Flask(__name__)
CORS(app)                                      # Allow cross-origin from React + ESP32
app.register_blueprint(detect_bp, url_prefix="/api")
app.register_blueprint(logs_bp,   url_prefix="/api")
```

### 8.3 Request Lifecycle — `POST /api/detect`

```
1.  Parse multipart form → image bytes, depth_mm, lat, lng

2.  yolo_runner.run_inference(image_bytes)
    ├── Load or reuse cached YOLOv8 model (_model global)
    ├── Decode JPEG → PIL Image → numpy array
    ├── Run model inference
    ├── Filter detections: confidence > 0.30
    └── Return [{area_px, confidence, bbox}, ...] + annotated base64 image

3.  Select detection with largest area_px (primary pothole)

4.  estimator.estimate_volume(area_px, depth_mm)
    ├── area_px × PX_TO_MM² → area_mm² → area_m²
    ├── depth_mm → depth_m
    └── volume = area_m² × depth_m × 0.7

5.  sheets.append_to_sheet(payload)
    └── Non-blocking: failure is caught and surfaced as sheets_warning field

6.  Return JSON: {status, timestamp, lat, lng, area_m2, depth_m,
                  volume_m3, volume_liters, confidence, annotated_image}
```

### 8.4 Dependencies

| Package         | Version | Purpose                                  |
| --------------- | ------- | ---------------------------------------- |
| `flask`         | 3.0.3   | HTTP server framework                    |
| `flask-cors`    | 4.0.1   | Cross-origin request headers             |
| `ultralytics`   | 8.2.0   | YOLOv8 model and inference utilities     |
| `Pillow`        | 10.3.0  | JPEG/PNG image decoding                  |
| `numpy`         | 1.26.4  | Array operations for image processing    |
| `gspread`       | 6.1.2   | Google Sheets client                     |
| `google-auth`   | 2.29.0  | Service account authentication           |
| `python-dotenv` | 1.0.1   | Environment variable loading from `.env` |

### 8.5 Environment Variables

```bash
# .env
GOOGLE_CREDS_JSON=credentials.json      # Path to service account key file
GOOGLE_SHEET_ID=your_sheet_id_here      # Google Sheet ID from URL
YOLO_WEIGHTS=yolov8n.pt                 # Or path to fine-tuned weights
```

---

## 9. Data Layer — Google Sheets

### 9.1 Design Rationale

Google Sheets was selected as the MVP data store because it is zero-cost, requires no database server setup or administration, provides an immediately accessible web UI for manual inspection, supports programmatic access via the Sheets API v4, and is sufficient for the detection volumes expected during MVP testing (hundreds to low thousands of rows).

### 9.2 Schema

| Column          | Type        | Description                                          |
| --------------- | ----------- | ---------------------------------------------------- |
| `timestamp`     | Integer     | Unix epoch timestamp of the detection event          |
| `datetime`      | String      | Human-readable local datetime (YYYY-MM-DD HH:MM:SS)  |
| `lat`           | Float       | WGS84 latitude (GPS or manually entered)             |
| `lng`           | Float       | WGS84 longitude                                      |
| `area_m2`       | Float       | Estimated pothole surface area in square metres      |
| `depth_m`       | Float       | Measured maximum depth in metres from ToF sensor     |
| `volume_m3`     | Float       | Estimated repair volume in cubic metres              |
| `volume_liters` | Float       | Estimated repair volume in litres (volume_m3 × 1000) |
| `confidence`    | Float (0–1) | YOLOv8 detection confidence score                    |

Headers are **auto-created on the first write** if the sheet is empty — no manual setup of column names required.

### 9.3 Setup Steps

1. Google Cloud Console → enable **Sheets API** and **Drive API**
2. Create a **Service Account** → download `credentials.json`
3. Share your Google Sheet with the service account email as **Editor**
4. Copy the Sheet ID from the URL: `docs.google.com/spreadsheets/d/<SHEET_ID>/edit`
5. Set `GOOGLE_SHEET_ID` and `GOOGLE_CREDS_JSON` in `.env`

### 9.4 Failure Handling

Sheets writes are wrapped in `try/except`. A Sheets API failure does **not** break the detection response — the full JSON result is still returned to the caller, and a `sheets_warning` field is appended to indicate the logging failure. This ensures the detection workflow is never blocked by transient network issues or quota limits.

---

## 10. Frontend Dashboard

### 10.1 Technology Choices

| Technology       | Choice                        | Rationale                                               |
| ---------------- | ----------------------------- | ------------------------------------------------------- |
| UI Framework     | React (JSX, hooks)            | Component model, clean state management, portable       |
| Mapping          | Leaflet.js (CDN)              | Free, no API key required, OpenStreetMap tiles          |
| Styling          | Inline styles + design tokens | No build step; token system ensures visual consistency  |
| State management | React `useState`              | Sufficient for MVP; no Redux overhead                   |
| HTTP client      | `fetch()` (native)            | No library dependency; supported in all modern browsers |

### 10.2 Layout

```
┌─────────────────────────────────────────────────────────────┐
│  HEADER — Logo  |  Status  |  API connectivity indicator    │
├──────────────────┬──────────────────────────────────────────┤
│                  │  DEFECT MAP (Leaflet.js)                  │
│  CONTROL PANEL   │  - OpenStreetMap base tiles              │
│                  │  - Amber glow pins per detection          │
│  - Image upload  │  - Click popup: depth, vol, confidence   │
│  - Annotated     ├──────────────────────────────────────────┤
│    preview       │  DETECTION LOG TABLE                      │
│  - Depth input   │  - Reverse chronological order           │
│  - GPS coords    │  - Colour-coded confidence badges        │
│  - Run button    │  - Volume highlighted in amber           │
│  - Latest stats  │  - Refresh button → GET /api/logs        │
│  - Session totals│                                          │
└──────────────────┴──────────────────────────────────────────┘
```

### 10.3 State Management

All state is managed with React `useState`. No external state library is needed at MVP scale.

| State Variable | Type            | Purpose                               |
| -------------- | --------------- | ------------------------------------- |
| `logs`         | Array           | All rows fetched from `/api/logs`     |
| `latest`       | Object          | Most recent detection result          |
| `imagePreview` | String (URL)    | Selected image before inference       |
| `annotatedImg` | String (base64) | Annotated image returned from backend |
| `depthMm`      | Number          | ToF depth input value                 |
| `lat`, `lng`   | String          | GPS coordinates for current scan      |
| `loading`      | Boolean         | Spinner state during API call         |
| `apiOk`        | Boolean         | Backend connectivity status           |
| `error`        | String          | Error message to display              |

### 10.4 Map Integration

Leaflet.js is injected dynamically (CSS `<link>` + JS `<script>`) on component mount to avoid a build-time npm dependency. Markers are re-rendered on `logs` state changes via a `useEffect`. The map auto-centres on the most recently logged coordinate with valid GPS data.

Each marker is rendered as a custom amber glow `divIcon`. Clicking a marker shows a popup with depth, volume, and confidence for that detection.

### 10.5 API Connectivity

On mount, the dashboard sends a `GET /api/logs` request to determine backend connectivity. A coloured status dot in the header shows green (online) or grey (offline). The API base URL is configurable via the `API_BASE` constant at the top of `App.jsx`.

---

## 11. API Reference

### `POST /api/detect`

Detect potholes in an image and estimate repair volume.

**Request — `multipart/form-data`**

| Field      | Type  | Required | Description                       |
| ---------- | ----- | -------- | --------------------------------- |
| `image`    | File  | ✅       | JPEG or PNG from ESP32-CAM        |
| `depth_mm` | Float | ✅       | ToF sensor reading in millimetres |
| `lat`      | Float | ❌       | GPS latitude (default 0)          |
| `lng`      | Float | ❌       | GPS longitude (default 0)         |

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

## 12. Cost Analysis

### 12.1 MVP Bill of Materials

| Item                           | Estimated Cost (INR) | Notes                                    |
| ------------------------------ | -------------------- | ---------------------------------------- |
| RC Chassis (rock crawler, 4WD) | ₹1,500 – ₹2,500      | High ground clearance                    |
| ESP32-CAM module               | ₹500 – ₹700          | Includes OV2640 camera                   |
| VL53L1X ToF sensor (breakout)  | ₹500 – ₹800          | I2C interface                            |
| 5V USB Power Bank              | ₹500                 | Powers ESP32 and sensor                  |
| Miscellaneous (wiring, mounts) | ₹200 – ₹400          | Jumper wires, brackets                   |
| Software (backend + frontend)  | ₹0                   | All open source; Google Sheets free tier |
| **Total**                      | **₹3,200 – ₹4,900**  | Well within typical hackathon/MVP budget |

### 12.2 Return on Investment

At an average repair cost of ₹800 per pothole (labour + asphalt) and a conservative **10% material wastage reduction** versus manual estimation, the system pays for its own hardware after approximately **5 repairs**. At municipal scale (500+ repairs per year), annual savings easily exceed ₹40,000 in material costs alone — excluding the additional value of reduced traffic disruption from faster, safer survey cycles.

---

## 13. Development Roadmap

| Phase       | Timeline | Deliverables                                                                                                                          |
| ----------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| **Phase 1** | Days 1–2 | Hardware integration: ESP32-CAM Wi-Fi connected, VL53L1X wired via I2C, basic HTTP POST from device to Flask server confirmed working |
| **Phase 2** | Day 3    | YOLOv8 inference running; volume calculation verified against artificial potholes of known geometry; PX_TO_MM calibrated              |
| **Phase 3** | Day 4    | Google Sheets pipeline live; `GET /api/logs` returning real data; React dashboard connected to backend                                |
| **Phase 4** | Day 5    | Leaflet map rendering geotagged pins; full end-to-end demo with RC robot on test surface; annotated images appearing in dashboard     |
| **Phase 5** | Buffer   | Bug fixes, calibration refinement, documentation, demo preparation                                                                    |

---

## 14. Known Limitations & Mitigations

| Limitation                                     | Impact                                       | Mitigation / Upgrade Path                                                                                                    |
| ---------------------------------------------- | -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Pretrained COCO weights (not pothole-specific) | Lower detection precision on actual potholes | Fine-tune YOLOv8 on Roboflow pothole dataset; target mAP50 > 0.75                                                            |
| Single ToF depth sample per frame              | Misses depth variation across defect span    | Multi-sample sweep; structured light scanner; LiDAR point cloud                                                              |
| No GPS on ESP32-CAM                            | Manual coordinate entry required per scan    | Add NEO-6M GPS module (~₹400); integrate NMEA parsing in ESP32 firmware                                                      |
| Dark asphalt degrades ToF accuracy             | Depth readings noisier on black bitumen      | Surface-specific calibration; production: industrial LiDAR                                                                   |
| Google Sheets as database                      | Not scalable beyond ~1,000 rows              | Migrate to SQLite (local) or Supabase (hosted Postgres) for production                                                       |
| No authentication on API                       | Open endpoint on local network               | Add `X-API-Key` header validation; deploy behind HTTPS reverse proxy                                                         |
| Heuristic volume correction (C_f = 0.7)        | ±15% volume estimation error                 | Empirically tune C_f per pothole morphology type; eventually replace with 3D mesh reconstruction from stereo camera or LiDAR |
| No real-time streaming                         | Snapshot-based detection only                | Implement MJPEG stream processing for continuous road scanning                                                               |

---

## 15. Future Work & Upgrade Path

### Phase 2 — Enhanced Accuracy

- Integrate NEO-6M GPS for automatic coordinate tagging without manual input
- Fine-tune YOLOv8 on domain-specific Indian road defect imagery
- Replace Google Sheets with Supabase (PostgreSQL) for scalable, queryable storage
- Add multi-defect classification: potholes, alligator cracking, rutting, edge breaks, longitudinal cracks

### Phase 3 — On-Device Intelligence

- Deploy TFLite quantized model directly on ESP32-S3 for edge inference without Wi-Fi dependency
- Implement offline buffering: store detections locally on SD card when Wi-Fi unavailable, sync on reconnect
- Replace single ToF sensor with RPLIDAR A1 for full 2D cross-section depth profiles per defect
- GPS integration for fully automatic geotagging without operator input

### Phase 4 — Civic Integration

- Compute full **Pavement Condition Index (PCI)** scores per road segment per ASTM D6433
- Automated repair priority queue based on PCI score, traffic volume, and repair cost model
- Public-facing transparency portal with defect status tracking: `Identified → In Progress → Resolved`
- Integration with municipal CMMS (Computerised Maintenance Management Systems)
- Contractor accountability module: photo-verified pre/post repair comparison

---

## 16. Conclusion

The Pavement Profiler demonstrates that the core components of an automated road assessment system can be assembled and deployed at under ₹5,000 in hardware costs. By combining a YOLOv8 computer vision model with a time-of-flight laser sensor and a lightweight data pipeline, the system produces objective, repeatable, geotagged pothole measurements that are demonstrably superior to manual inspection practices on the dimensions of cost, speed, safety, and data quality.

The MVP establishes the technical foundation for a scalable infrastructure tool. Each component — the detection model, the volume estimator, the data pipeline, and the visualization layer — is independently upgradeable without disrupting the others. The architecture is intentionally modular precisely to enable this incremental improvement path.

Most significantly, the system converts an inherently subjective manual process into an objective, auditable data stream. This shift from opinion-based to measurement-based road maintenance has the potential to improve resource allocation, reduce material wastage, shorten response timelines, and strengthen public accountability in infrastructure management — all from a platform that costs less than a tank of fuel.

---

_Pavement Profiler — Project Documentation | MVP Release | 2025_
