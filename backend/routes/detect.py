import base64
import time

from flask import Blueprint, request, jsonify
from utils.material_estimator import (
    estimate_volume, predict_materials_ml,
    REPAIR_METHODS, REPAIR_METHODS_CRACK,
)
from utils.database import insert_detection
from utils.yolo_runner import run_inference

detect_bp = Blueprint("detect", __name__)


def _get_repair_method(defect_type, severity):
    if defect_type == "crack":
        return REPAIR_METHODS_CRACK.get(severity, "Unknown")
    return REPAIR_METHODS.get(severity, "Unknown")


@detect_bp.route("/detect", methods=["POST"])
def detect():
    try:
        if request.content_type and "multipart" in request.content_type:
            image_file = request.files.get("image")
            image_bytes = image_file.read()
            depth_mm = float(request.form.get("depth_mm", 0))
            lat = float(request.form.get("lat", 0.0))
            lng = float(request.form.get("lng", 0.0))
        else:
            data = request.get_json()
            img_b64 = data.get("image", "")
            image_bytes = base64.b64decode(img_b64)
            depth_mm = float(data.get("depth_mm", 0))
            lat = float(data.get("lat", 0.0))
            lng = float(data.get("lng", 0.0))

        detections, annotated_b64 = run_inference(image_bytes)

        if not detections:
            return jsonify({"status": "no_defect", "message": "No defect detected"}), 200

        best = max(detections, key=lambda d: d["area_px"])
        defect_type = best.get("defect_type", "pothole")

        vol = estimate_volume(
            area_px=best["area_px"],
            depth_mm=depth_mm,
        )

        materials = predict_materials_ml(
            area_m2=vol["area_m2"],
            depth_m=vol["depth_m"],
            volume_liters=vol["volume_liters"],
            defect_type=defect_type,
        )

        severity = materials.get('severity', 'MEDIUM')

        materials_out = {k: v for k, v in materials.items()
                         if k not in ("severity", "prediction_source")}

        payload = {
            "status": "defect_detected",
            "defect_type": defect_type,
            "timestamp": int(time.time()),
            "lat": lat,
            "lng": lng,
            "area_m2": vol["area_m2"],
            "depth_m": vol["depth_m"],
            "volume_m3": vol["volume_m3"],
            "volume_liters": vol["volume_liters"],
            "volume_min_liters": vol["volume_min_liters"],
            "volume_max_liters": vol["volume_max_liters"],
            "confidence": best["confidence"],
            "severity": severity,
            "repair_method": _get_repair_method(defect_type, severity),
            "materials": materials_out,
            "prediction_source": materials.get("prediction_source", "RULE_BASED"),
            "annotated_image": annotated_b64,
        }

        try:
            insert_detection(payload)
        except Exception as e:
            payload["db_warning"] = str(e)

        return jsonify(payload), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500
