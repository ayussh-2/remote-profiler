"""Batched detection logger with spatial deduplication."""

import threading
import time
import math

from utils.database import insert_detection


def _haversine_m(lat1, lng1, lat2, lng2):
    R = 6371000
    rlat1, rlat2 = math.radians(lat1), math.radians(lat2)
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = math.sin(dlat / 2) ** 2 + math.cos(rlat1) * math.cos(rlat2) * math.sin(dlng / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


class BatchLogger:
    def __init__(self, flush_interval=30, flush_count=10, dedup_radius_m=5.0, dedup_window_s=60):
        self._buffer = []
        self._lock = threading.Lock()
        self._flush_interval = flush_interval
        self._flush_count = flush_count
        self._dedup_radius = dedup_radius_m
        self._dedup_window = dedup_window_s
        self._recent = []
        self._timer = None
        self._running = False

    def start(self):
        self._running = True
        self._schedule_flush()

    def stop(self):
        self._running = False
        if self._timer:
            self._timer.cancel()
        self._flush()

    def _schedule_flush(self):
        if not self._running:
            return
        self._timer = threading.Timer(self._flush_interval, self._timed_flush)
        self._timer.daemon = True
        self._timer.start()

    def _timed_flush(self):
        self._flush()
        self._schedule_flush()

    def _is_duplicate(self, payload):
        lat, lng = payload.get("lat", 0), payload.get("lng", 0)
        if lat == 0 and lng == 0:
            return False

        now = time.time()
        self._recent = [r for r in self._recent if now - r["t"] < self._dedup_window]

        for r in self._recent:
            dist = _haversine_m(lat, lng, r["lat"], r["lng"])
            if dist < self._dedup_radius:
                return True
        return False

    def add(self, payload: dict):
        with self._lock:
            if self._is_duplicate(payload):
                return

            self._buffer.append(payload)
            self._recent.append({
                "lat": payload.get("lat", 0),
                "lng": payload.get("lng", 0),
                "t": time.time(),
            })

            if len(self._buffer) >= self._flush_count:
                self._flush_locked()

    def _flush(self):
        with self._lock:
            self._flush_locked()

    def _flush_locked(self):
        if not self._buffer:
            return

        batch = list(self._buffer)
        self._buffer.clear()

        for payload in batch:
            try:
                insert_detection(payload)
            except Exception as e:
                print(f"[BatchLogger] Sheet write failed: {e}")
