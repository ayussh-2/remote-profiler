"""YOLOv8 inference wrapper for pothole/crack detection."""

import io
import base64
import os

from PIL import Image
import numpy as np
import torch

_model = None
_device = None


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
        from ultralytics import YOLO
        weights = os.environ.get("YOLO_WEIGHTS", "yolov8n.pt")
        _model = YOLO(weights)
        print(f"[YOLO] Loaded weights: {weights}")
    return _model


def run_inference(image_bytes: bytes) -> tuple[list[dict], str]:
    image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    img_array = np.array(image)

    model = get_model()
    device = get_device()
    results = model(img_array, device=device, verbose=False)
    result = results[0]

    pothole_class_id = int(os.environ.get("YOLO_CLASS_ID", 0))
    weights = os.environ.get("YOLO_WEIGHTS", "yolov8n.pt")
    is_custom_weights = weights != "yolov8n.pt"

    detections = []
    for box in result.boxes:
        cls_id = int(box.cls[0])
        conf = float(box.conf[0])

        if conf < 0.3:
            continue
        if is_custom_weights and cls_id != pothole_class_id:
            continue

        x1, y1, x2, y2 = box.xyxy[0].tolist()
        area_px = (x2 - x1) * (y2 - y1)

        detections.append({
            "area_px": area_px,
            "confidence": round(conf, 3),
            "bbox": [x1, y1, x2, y2],
            "class_id": cls_id,
        })

    annotated_array = result.plot()
    annotated_image = Image.fromarray(annotated_array)
    buf = io.BytesIO()
    annotated_image.save(buf, format="JPEG", quality=85)
    annotated_b64 = base64.b64encode(buf.getvalue()).decode("utf-8")

    return detections, annotated_b64
