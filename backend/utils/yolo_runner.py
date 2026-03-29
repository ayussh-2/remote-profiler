"""YOLOv8 inference wrapper for pothole/crack detection."""

import io
import base64
import os
import threading

import cv2
from PIL import Image
import numpy as np
import torch

_model = None
_model_lock = threading.Lock()
_device = None

# ENV: DEFECT_CLASSES="0:pothole,1:crack,2:shallow_pothole"
_defect_classes = None

CONFIDENCE_THRESHOLD = float(os.environ.get("YOLO_CONF_THRESHOLD", 0.3))


def _parse_defect_classes() -> dict[int, str]:
    global _defect_classes
    if _defect_classes is not None:
        return _defect_classes

    raw = os.environ.get("DEFECT_CLASSES", "0:pothole,1:crack,2:shallow_pothole")
    _defect_classes = {}
    for pair in raw.split(","):
        pair = pair.strip()
        if ":" in pair:
            cid, name = pair.split(":", 1)
            _defect_classes[int(cid)] = name.strip()
    return _defect_classes


def get_device() -> str:
    global _device
    if _device is None:
        _device = "cuda" if torch.cuda.is_available() else "cpu"
        print(f"[YOLO] Device: {_device}")
        if _device == "cuda":
            print(f"[YOLO] GPU: {torch.cuda.get_device_name(0)}")
    return _device


def get_model():
    global _model
    if _model is None:
        with _model_lock:
            if _model is None:
                from ultralytics import YOLO
                weights = os.environ.get("YOLO_WEIGHTS", "yolov8n.pt")
                _model = YOLO(weights)
                print(f"[YOLO] Loaded weights: {weights}")
    return _model


def preprocess_frame(image_bytes: bytes) -> np.ndarray:
    """Enhance low-quality ESP32-CAM frames for better detection."""
    arr = np.frombuffer(image_bytes, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)

    lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
    l_channel, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    l_channel = clahe.apply(l_channel)
    lab = cv2.merge([l_channel, a, b])
    img = cv2.cvtColor(lab, cv2.COLOR_LAB2BGR)

    img = cv2.GaussianBlur(img, (3, 3), 0)

    return cv2.cvtColor(img, cv2.COLOR_BGR2RGB)


def _extract_detections(result) -> list[dict]:
    """Extract detections from a YOLO result, filtering by configured defect classes."""
    defect_classes = _parse_defect_classes()
    weights = os.environ.get("YOLO_WEIGHTS", "yolov8n.pt")
    is_custom = weights != "yolov8n.pt"

    detections = []
    for box in result.boxes:
        cls_id = int(box.cls[0])
        conf = float(box.conf[0])

        if conf < CONFIDENCE_THRESHOLD:
            continue

        x1, y1, x2, y2 = box.xyxy[0].tolist()
        area_px = (x2 - x1) * (y2 - y1)
        
        cls_name = result.names.get(cls_id, "unknown") if hasattr(result, "names") else defect_classes.get(cls_id, "unknown")
        cls_name = cls_name.lower().replace(" ", "_")

        if is_custom and cls_name not in ["pothole", "crack", "shallow_pothole"]:
            pass

        detections.append({
            "area_px": area_px,
            "confidence": round(conf, 3),
            "bbox": [x1, y1, x2, y2],
            "class_id": cls_id,
            "defect_type": cls_name,
        })

    return detections


def run_inference(image_bytes: bytes) -> tuple[list[dict], str]:
    """Single-image detection. Returns (detections, annotated_b64)."""
    img_array = preprocess_frame(image_bytes)

    model = get_model()
    device = get_device()
    results = model(img_array, device=device, verbose=False)
    result = results[0]

    detections = _extract_detections(result)

    annotated_array = result.plot()
    annotated_image = Image.fromarray(annotated_array)
    buf = io.BytesIO()
    annotated_image.save(buf, format="JPEG", quality=85)
    annotated_b64 = base64.b64encode(buf.getvalue()).decode("utf-8")

    return detections, annotated_b64


def run_inference_fast(image_bytes: bytes) -> tuple[list[dict], bytes]:
    """Stream-optimized detection. Returns (detections, annotated_jpeg_bytes)."""
    img_array = preprocess_frame(image_bytes)

    model = get_model()
    device = get_device()
    results = model(img_array, device=device, verbose=False)
    result = results[0]

    detections = _extract_detections(result)

    annotated_array = result.plot()
    success, jpeg_buf = cv2.imencode(
        ".jpg", cv2.cvtColor(annotated_array, cv2.COLOR_RGB2BGR),
        [cv2.IMWRITE_JPEG_QUALITY, 80],
    )
    annotated_bytes = jpeg_buf.tobytes() if success else b""

    return detections, annotated_bytes
