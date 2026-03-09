# Pavement Profiler — Backend

Flask API for pothole detection, volume estimation, and Google Sheets logging.

## Stack

- Python 3.12
- Flask 3.1 + Flask-CORS
- YOLOv8 (ultralytics)
- gspread (Google Sheets)
- VL53L1X ToF depth input (via ESP32-CAM POST)

## Structure

```
backend/
├── app.py                  # entry point
├── requirements.txt
├── .env.example
├── routes/
│   ├── detect.py           # POST /api/detect
│   └── logs.py             # GET  /api/logs
└── utils/
    ├── yolo_runner.py      # YOLO inference
    ├── estimator.py        # volume math (A x Z x 0.7)
    └── sheets.py           # Google Sheets read/write
```

## Setup

```powershell
cd backend
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## Environment

```powershell
cp .env.example .env
```

Edit `.env`:

```env
GOOGLE_SHEET_ID=your_sheet_id_here
GOOGLE_CREDS_JSON=credentials.json
YOLO_WEIGHTS=best.pt
YOLO_CLASS_ID=0
```

### Google Sheets setup

1. Google Cloud Console → enable **Sheets API** + **Drive API**
2. Create a Service Account → download credentials JSON → place at `backend/credentials.json`
3. Share your sheet with the service account email (Editor)
4. Copy the sheet ID from the URL: `docs.google.com/spreadsheets/d/<SHEET_ID>/edit`

### YOLO weights

- MVP: download a pretrained pothole model from https://universe.roboflow.com/search?q=pothole
- Export as `YOLOv8 PyTorch` → rename to `best.pt` → place in `backend/`
- Set `YOLO_WEIGHTS=best.pt` in `.env`
- Default (`yolov8n.pt`) is COCO pretrained — useful for pipeline testing only

## Run

```powershell
.\venv\Scripts\Activate.ps1
python app.py
# API live at http://localhost:5000
```

## API

### `POST /api/detect`

Accepts `multipart/form-data`:

| Field      | Type  | Description                 |
| ---------- | ----- | --------------------------- |
| `image`    | file  | JPEG/PNG from ESP32-CAM     |
| `depth_mm` | float | ToF reading in mm (VL53L1X) |
| `lat`      | float | GPS latitude (optional)     |
| `lng`      | float | GPS longitude (optional)    |

Response:

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

### `GET /api/logs`

Returns all rows from Google Sheets as a JSON array.

```json
{ "status": "ok", "data": [ ... ] }
```

## Volume Formula

```
V = A x Z x 0.7
```

- `A` — pothole surface area in m² (pixel area × calibration constant)
- `Z` — max depth in m (from ToF sensor)
- `0.7` — bowl-shape correction factor

Calibration: edit `PX_TO_MM` in [utils/estimator.py](utils/estimator.py) by measuring a known object at your camera mount height.
