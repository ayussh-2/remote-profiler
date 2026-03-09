"""
YOLOv8 inference wrapper.
Uses ultralytics YOLOv8 with a pretrained COCO model for MVP.
For production: fine-tune on pothole dataset (e.g. Roboflow pothole dataset).
"""

import io, base64, os
from PIL import Image
import numpy as np

# Lazy-load model to avoid slow startup
_model = None

def get_model():
    global _model
    if _model is None:
        from ultralytics import YOLO
        weights = os.environ.get("YOLO_WEIGHTS", "yolov8n.pt")
        _model = YOLO(weights)
    return _model


def run_inference(image_bytes: bytes) -> tuple[list[dict], str]:
    """
    Run YOLO inference on raw image bytes.
    Returns:
        detections: list of {area_px, confidence, bbox}
        annotated_b64: base64 encoded annotated image
    """
    # Decode image
    image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    img_array = np.array(image)

    model = get_model()

    # Run inference
    results = model(img_array, verbose=False)
    result = results[0]

    # class 0 = pothole in all standard pothole YOLO datasets
    POTHOLE_CLASS_ID = int(os.environ.get("YOLO_CLASS_ID", 0))

    detections = []
    for box in result.boxes:
        cls_id = int(box.cls[0])
        conf = float(box.conf[0])

        if conf < 0.3:
            continue
        # When using COCO weights (no pothole class), skip class filter for demo
        weights = os.environ.get("YOLO_WEIGHTS", "yolov8n.pt")
        if weights != "yolov8n.pt" and cls_id != POTHOLE_CLASS_ID:
            continue

        x1, y1, x2, y2 = box.xyxy[0].tolist()
        width_px = x2 - x1
        height_px = y2 - y1
        area_px = width_px * height_px

        detections.append({
            "area_px": area_px,
            "confidence": round(conf, 3),
            "bbox": [x1, y1, x2, y2],
            "class_id": cls_id,
        })

    # Generate annotated image
    annotated_array = result.plot()
    annotated_image = Image.fromarray(annotated_array)
    buf = io.BytesIO()
    annotated_image.save(buf, format="JPEG", quality=85)
    annotated_b64 = base64.b64encode(buf.getvalue()).decode("utf-8")

    return detections, annotated_b64
