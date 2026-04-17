# Pavement Profiler — Backend

Flask API for pothole detection, volume estimation, and Google Sheets logging.

---

## GPU Support (Optional but Recommended)

> **For production deployments with NVIDIA GPUs: significantly faster inference (20-30x speedup).**

### Quick Start (GPU)

The backend now supports both CPU and GPU inference. **PyTorch will automatically use GPU if CUDA is available.**

#### Prerequisites

- NVIDIA GPU (Compute Capability ≥ 3.5)
- CUDA Toolkit 12.1+ ([Download](https://developer.nvidia.com/cuda-downloads))
- cuDNN 9.0+ ([Download](https://developer.nvidia.com/cudnn))

#### Installation

**Linux/macOS:**

```bash
python -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install torch==2.11.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
pip install -r requirements.txt
# Verify GPU
python -c "import torch; print(f'GPU: {torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"Not available\"}')"
```

**Windows:**

```powershell
python -m venv venv
.\venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install torch==2.11.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
pip install -r requirements.txt
# Verify GPU
python -c "import torch; print(f'GPU: {torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"Not available\"}')"
```

**Docker:**

```bash
docker build -f Dockerfile.gpu -t profiler-backend:gpu .
docker run --gpus all -p 5000:5000 -e FLASK_ENV=production profiler-backend:gpu
```

### Performance (GPU vs CPU)

| Operation           | CPU (i7-12700K) | GPU (RTX 3070) | Speedup    |
| ------------------- | --------------- | -------------- | ---------- |
| YOLOv8 Inference    | 450-550ms       | 15-25ms        | **20-30x** |
| Material Estimation | 5-10ms          | 5-10ms         | ~1x        |
| **Total Latency**   | **480-600ms**   | **50-80ms**    | **8-10x**  |
| **Throughput**      | **~2 fps**      | **~15-20 fps** | **~10x**   |

### Troubleshooting GPU

1. **NVIDIA drivers not installed:**

    ```bash
    nvidia-smi  # Should show GPU info
    ```

    If not found, [install NVIDIA drivers](https://www.nvidia.com/Download/driverDetails.aspx).

2. **CUDA not detected in PyTorch:**

    ```bash
    python -c "import torch; print(torch.cuda.is_available())"  # Should be True
    ```

    If `False`, reinstall PyTorch with CUDA support (see Installation above).

3. **Force CPU mode (for debugging):**
    ```bash
    export CUDA_VISIBLE_DEVICES=""  # Linux/macOS
    # or
    $env:CUDA_VISIBLE_DEVICES=""    # PowerShell
    python app.py
    ```

---

## For the Model / Dataset Owner

> **If you trained the YOLOv8 model and just need to plug it in, read this section.**

### 1. Drop your weights file into `backend/`

After training, export your best weights as a `.pt` file (YOLOv8 PyTorch format) and copy it here:

```
backend/
└── best.pt          ← place your trained weights here
```

Any filename works — you just tell the app where it is via `.env` (see step 2).

### 2. Set environment variables

Open (or create) `backend/.env` and set:

```env
YOLO_WEIGHTS=best.pt        # filename of your weights file (relative to backend/)
YOLO_CLASS_ID=0             # the class index your model uses for "pothole"
                            # — check your dataset's data.yaml: names[0] should be "pothole"
```

`YOLO_CLASS_ID=0` is the standard for every public pothole dataset on Roboflow. If your `data.yaml` has pothole at a different index, update this accordingly.

### 3. How your model is used (the inference pipeline)

```
ESP32-CAM image (JPEG bytes)
        │
        ▼
utils/yolo_runner.py  ──► loads your best.pt once (lazy, cached)
        │                   runs model(img_array)
        │                   filters boxes: conf ≥ 0.3  AND  cls == YOLO_CLASS_ID
        │                   returns list of { area_px, confidence, bbox }
        ▼
routes/detect.py      ──► picks the largest detection (highest area_px)
        │
        ▼
utils/estimator.py    ──► converts area_px + depth_mm → volume
        │                   area_m2 = area_px × (PX_TO_MM)²  / 1_000_000
        │                   volume  = area_m2 × depth_m × 0.7
        ▼
Google Sheets + JSON response
```

### 4. Confidence threshold

In `utils/yolo_runner.py` line ~44:

```python
if conf < 0.3:
    continue
```

Default is **0.3**. If your model is well-trained and you want fewer false positives, raise it to `0.5`. Edit directly in the file.

### 5. Pixel-to-mm calibration

In `utils/estimator.py`:

```python
PX_TO_MM = 0.5   # mm per pixel at ~30 cm camera height
```

This converts the bounding-box pixel area into real-world area. It was set assuming the camera sits ~30 cm above the road. If your dataset was captured at a different mounting height, adjust this constant — place a card of known size (e.g. A4 = 210 × 297 mm) flat on the ground, run an image through the API, and tune `PX_TO_MM` until the reported `area_m2` is correct.

### 6. Quick sanity check

Once the server is running, you can test your model directly with curl:

```powershell
curl -X POST http://localhost:5000/api/detect `
  -F "image=@test_pothole.jpg" `
  -F "depth_mm=80"
```

Expected response shape:

```json
{
    "status": "pothole_detected",
    "area_m2": 0.042,
    "depth_m": 0.08,
    "volume_m3": 0.00235,
    "volume_liters": 2.35,
    "confidence": 0.87,
    "annotated_image": "<base64 JPEG>"
}
```

If you get `"status": "no_pothole"`, the model either didn't detect anything above the confidence threshold or the class ID doesn't match — double-check `YOLO_CLASS_ID` and your `data.yaml`.

---

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
    ├── yolo_runner.py      # YOLO inference  ← loads your weights
    ├── estimator.py        # volume math (A x Z x 0.7)  ← tune PX_TO_MM here
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
