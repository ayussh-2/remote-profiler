# Pavement Profiler — MVP

Automated road defect detection system using YOLOv8 + ToF depth sensor.

---

## Project Structure

```
pavement-profiler/
├── backend/
│   ├── app.py                  # Flask entry point
│   ├── requirements.txt
│   ├── .env.example
│   ├── routes/
│   │   ├── detect.py           # POST /api/detect  ← core endpoint
│   │   └── logs.py             # GET  /api/logs
│   └── utils/
│       ├── yolo_runner.py      # YOLOv8 inference
│       ├── estimator.py        # Volume math (A × Z × 0.7)
│       └── sheets.py           # Google Sheets read/write
└── frontend/
    └── src/
        └── App.jsx             # React dashboard (map + logs + upload)
```

---

## Backend Setup

### 1. Install dependencies
```bash
cd backend
pip install -r requirements.txt
```

### 2. Configure environment
```bash
cp .env.example .env
# Edit .env and fill in:
#   GOOGLE_SHEET_ID   = your sheet ID (from URL)
#   GOOGLE_CREDS_JSON = path to service account JSON
#   YOLO_WEIGHTS      = yolov8n.pt  (or path to fine-tuned weights)
```

### 3. Google Sheets setup
1. Go to Google Cloud Console → enable **Google Sheets API** + **Google Drive API**
2. Create a **Service Account** → download the credentials JSON
3. Open your Google Sheet → Share it with the service account email (Editor)
4. Copy the Sheet ID from the URL: `docs.google.com/spreadsheets/d/<SHEET_ID>/edit`

### 4. YOLO weights
- MVP: downloads `yolov8n.pt` (COCO pretrained) automatically on first run
- For actual pothole detection, fine-tune on a pothole dataset:
  - https://universe.roboflow.com/search?q=pothole
  - Set `YOLO_WEIGHTS=path/to/pothole_best.pt` in `.env`

### 5. Run the server
```bash
python app.py
# Server starts at http://localhost:5000
```

---

## API Reference

### POST `/api/detect`
Accepts an image + depth reading, returns volume estimate.

**Form-data:**
| Field      | Type   | Description                        |
|------------|--------|------------------------------------|
| `image`    | file   | JPEG/PNG from ESP32-CAM            |
| `depth_mm` | float  | ToF reading in mm (VL53L1X)        |
| `lat`      | float  | GPS latitude (optional)            |
| `lng`      | float  | GPS longitude (optional)           |

**Response:**
```json
{
  "status": "pothole_detected",
  "timestamp": 1718000000,
  "lat": 12.9716,
  "lng": 77.5946,
  "area_m2": 0.042,
  "depth_m": 0.08,
  "volume_m3": 0.00235,
  "volume_liters": 2.35,
  "confidence": 0.87,
  "annotated_image": "<base64 JPEG>"
}
```

### GET `/api/logs`
Returns all rows from Google Sheets.

---

## Frontend Setup

The `App.jsx` is a standalone React component. Drop it into:
- Any Vite/CRA React project, OR
- Paste directly into Claude.ai artifacts to preview

**To run as a full app:**
```bash
npm create vite@latest frontend -- --template react
cd frontend
cp ../src/App.jsx src/App.jsx
npm run dev
```

---

## ESP32-CAM Integration

To send data from the robot, upload this sketch logic:
```cpp
// After capturing image + reading ToF sensor:
HTTPClient http;
http.begin("http://<your-laptop-ip>:5000/api/detect");
http.addHeader("Content-Type", "multipart/form-data; boundary=----boundary");

// Build multipart body with: image, depth_mm, lat, lng
// (Use ArduinoHttpClient or manual multipart construction)
```

---

## Volume Formula

```
V = A × Z_max × 0.7
```
- `A`   = pothole area in m² (pixel area × calibration constant)
- `Z`   = max depth in m (from VL53L1X ToF)
- `0.7` = correction factor for bowl-shaped geometry
- Expected error margin: ±15% (better than manual ±20%)

---

## Calibration

Edit `backend/utils/estimator.py`:
```python
PX_TO_MM = 0.5  # Measure a known object at camera mount height to calibrate
```

---

## Week Plan

| Day | Task |
|-----|------|
| Mon | Backend running, `/detect` endpoint tested with static image |
| Tue | YOLO inference working (even with pretrained weights) |
| Wed | Google Sheets logging live |
| Thu | Frontend connected to backend, map showing pins |
| Fri | End-to-end test with actual RC car + ESP32-CAM |
| Sat | Buffer / polish |
