"""ESP32-CAM frame ingestion + Socket.IO broadcasting to viewing clients."""

import base64
import time
import threading

import eventlet
from eventlet import tpool
from flask import Blueprint, request

from utils.yolo_runner import run_inference_fast
from utils.material_estimator import estimate_volume, estimate_repair
from utils.batch_logger import BatchLogger
from utils.frame_tracker import FrameTracker

stream_bp = Blueprint("stream", __name__)

_frame_lock = threading.Lock()
_latest_frame = None
_stream_active = False
_processing_thread = None
_viewer_count = 0

_batch_logger = BatchLogger(flush_interval=30, flush_count=10)

# Set by init_stream_events() when socketio is available
_socketio = None


def init_stream_events(socketio):
    """Register Socket.IO event handlers. Called from app.py after socketio is created."""
    global _socketio
    _socketio = socketio

    @socketio.on("connect")
    def on_connect():
        global _viewer_count
        _viewer_count += 1
        socketio.emit("viewer_count", {"count": _viewer_count})

    @socketio.on("disconnect")
    def on_disconnect():
        global _viewer_count
        _viewer_count = max(0, _viewer_count - 1)
        socketio.emit("viewer_count", {"count": _viewer_count})


def _start_processing():
    global _stream_active, _processing_thread
    if _stream_active:
        return

    _stream_active = True
    _batch_logger.start()
    _processing_thread = eventlet.spawn(_processing_loop)
    print("[Stream] Processing started")


@stream_bp.route("/stream/frame", methods=["POST"])
def receive_frame():
    """ESP32 posts JPEG frames + sensor data here."""
    global _latest_frame

    if not _stream_active:
        _start_processing()

    image_file = request.files.get("image")
    if not image_file:
        return "", 400

    image_bytes = image_file.read()
    depth_mm = float(request.form.get("depth_mm", 0))
    lat = float(request.form.get("lat", 0.0))
    lng = float(request.form.get("lng", 0.0))

    with _frame_lock:
        _latest_frame = {
            "image_bytes": image_bytes,
            "depth_mm": depth_mm,
            "lat": lat,
            "lng": lng,
            "received_at": time.time(),
        }

    return "", 204


_IDLE_TIMEOUT = 10

def _processing_loop():
    global _latest_frame, _stream_active

    _fps_counter = {"count": 0, "last_reset": time.time()}
    last_frame_at = time.time()
    tracker = FrameTracker(iou_threshold=0.25, max_missing=8)

    while _stream_active:
        with _frame_lock:
            frame = _latest_frame
            _latest_frame = None

        if frame is None:
            if time.time() - last_frame_at > _IDLE_TIMEOUT:
                _stream_active = False
                _batch_logger.stop()
                print("[Stream] No frames for %ds -- auto-stopped", _IDLE_TIMEOUT)
                break
            eventlet.sleep(0.01)
            continue

        last_frame_at = time.time()

        try:
            detections, annotated_bytes = tpool.execute(run_inference_fast, frame["image_bytes"])

            results = []
            for det in detections:
                vol = estimate_volume(
                    area_px=det["area_px"],
                    depth_mm=frame["depth_mm"],
                )
                repair = estimate_repair(
                    area_m2=vol["area_m2"],
                    depth_m=vol["depth_m"],
                    volume_liters=vol["volume_liters"],
                    defect_type=det.get("defect_type", "pothole"),
                )
                results.append({
                    "defect_type": det.get("defect_type", "unknown"),
                    "confidence": det["confidence"],
                    "bbox": det["bbox"],
                    **vol,
                    **repair,
                })

            tracked, new_dets = tracker.update(results)
            all_dets = tracked + new_dets

            _fps_counter["count"] += 1
            now = time.time()
            elapsed = now - _fps_counter["last_reset"]
            fps = _fps_counter["count"] / elapsed if elapsed > 0 else 0
            if elapsed >= 2.0:
                _fps_counter["count"] = 0
                _fps_counter["last_reset"] = now

            annotated_b64 = base64.b64encode(annotated_bytes).decode("utf-8")

            for d in all_dets:
                d["is_new"] = d["frames_seen"] == 1

            if _socketio:
                _socketio.emit("stream_frame", {
                    "image": annotated_b64,
                    "detections": all_dets,
                    "fps": round(fps, 1),
                    "timestamp": now,
                    "viewer_count": _viewer_count,
                })

            for r in new_dets:
                _batch_logger.add({
                    "timestamp": int(now),
                    "lat": frame["lat"],
                    "lng": frame["lng"],
                    "area_m2": r.get("area_m2", 0),
                    "depth_m": r.get("depth_m", 0),
                    "volume_m3": r.get("volume_m3", 0),
                    "volume_liters": r.get("volume_liters", 0),
                    "confidence": r.get("confidence", 0),
                    "severity": r.get("severity", ""),
                    "defect_type": r.get("defect_type", "pothole"),
                })

        except Exception as e:
            print(f"[Stream] Processing error: {e}")
            eventlet.sleep(0.05)

        eventlet.sleep(0)
