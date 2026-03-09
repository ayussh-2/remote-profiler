from flask import Blueprint, request, jsonify
from utils.estimator import estimate_volume
from utils.sheets import append_to_sheet
from utils.yolo_runner import run_inference
import base64, io, time

detect_bp = Blueprint("detect", __name__)

@detect_bp.route("/detect", methods=["POST"])
def detect():
    """
    Expects multipart/form-data OR JSON with:
      - image: base64 encoded image OR file upload
      - depth_mm: float (from VL53L1X ToF sensor, in millimeters)
      - lat: float (optional GPS latitude)
      - lng: float (optional GPS longitude)
    """
    try:
        # --- Parse inputs ---
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

        # --- Run YOLO inference ---
        detections, annotated_b64 = run_inference(image_bytes)

        if not detections:
            return jsonify({"status": "no_pothole", "message": "No pothole detected"}), 200

        # Use largest detected pothole
        best = max(detections, key=lambda d: d["area_px"])

        # --- Volume estimation ---
        result = estimate_volume(
            area_px=best["area_px"],
            depth_mm=depth_mm,
            confidence=best["confidence"],
        )

        # --- Build response payload ---
        payload = {
            "status": "pothole_detected",
            "timestamp": int(time.time()),
            "lat": lat,
            "lng": lng,
            "area_m2": result["area_m2"],
            "depth_m": result["depth_m"],
            "volume_m3": result["volume_m3"],
            "volume_liters": result["volume_liters"],
            "confidence": best["confidence"],
            "annotated_image": annotated_b64,
        }

        # --- Log to Google Sheets (non-blocking) ---
        try:
            append_to_sheet(payload)
        except Exception as e:
            payload["sheets_warning"] = str(e)

        return jsonify(payload), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500
