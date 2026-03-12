from flask import Blueprint, request, jsonify
from utils.estimator import estimate_volume
from utils.material_estimator import estimate_repair
from utils.sheets import append_to_sheet
from utils.yolo_runner import run_inference
import base64, time

detect_bp = Blueprint("detect", __name__)


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
            return jsonify({"status": "no_pothole", "message": "No pothole detected"}), 200

        best = max(detections, key=lambda d: d["area_px"])

        vol = estimate_volume(
            area_px=best["area_px"],
            depth_mm=depth_mm,
            confidence=best["confidence"],
        )

        repair = estimate_repair(
            area_m2=vol["area_m2"],
            depth_m=vol["depth_m"],
            volume_m3=vol["volume_m3"],
            volume_liters=vol["volume_liters"],
        )

        payload = {
            "status": "pothole_detected",
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
            "severity": repair["severity"],
            "repair_method": repair["repair_method"],
            "materials": repair["materials"],
            "estimated_cost_inr": repair["estimated_cost_inr"],
            "annotated_image": annotated_b64,
        }

        try:
            append_to_sheet(payload)
        except Exception as e:
            payload["sheets_warning"] = str(e)

        return jsonify(payload), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500
