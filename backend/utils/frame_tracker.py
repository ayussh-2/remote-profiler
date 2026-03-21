"""IoU-based frame-to-frame object tracker for deduplicating detections across
consecutive video frames. Assigns stable track IDs so the same physical defect
seen over many frames is only logged / emitted as 'new' once."""


def _iou(a, b):
    """Intersection-over-Union for two [x1, y1, x2, y2] boxes."""
    ix1, iy1 = max(a[0], b[0]), max(a[1], b[1])
    ix2, iy2 = min(a[2], b[2]), min(a[3], b[3])
    inter = max(0, ix2 - ix1) * max(0, iy2 - iy1)
    if inter == 0:
        return 0.0
    area_a = (a[2] - a[0]) * (a[3] - a[1])
    area_b = (b[2] - b[0]) * (b[3] - b[1])
    return inter / (area_a + area_b - inter)


class FrameTracker:
    """Lightweight greedy IoU tracker.

    - ``update(detections)`` matches the current frame's detections to existing
      tracks via bounding-box IoU.  Each detection dict **must** contain a
      ``"bbox"`` key with ``[x1, y1, x2, y2]``.
    - Returns ``(matched_results, new_results)`` where each item is the
      original detection dict augmented with ``"track_id"`` and
      ``"frames_seen"`` (how many consecutive frames this track has survived).
    - Tracks that go unseen for ``max_missing`` frames are expired.
    """

    def __init__(self, iou_threshold=0.25, max_missing=8):
        self._iou_thresh = iou_threshold
        self._max_missing = max_missing
        self._tracks = {}          # track_id -> {bbox, missing, frames_seen}
        self._next_id = 0

    def update(self, detections: list[dict]):
        unmatched_dets = list(range(len(detections)))
        matched_pairs = []         # (track_id, det_index)

        # greedy matching: highest IoU first
        candidates = []
        for tid, track in self._tracks.items():
            for di in unmatched_dets:
                score = _iou(track["bbox"], detections[di]["bbox"])
                if score >= self._iou_thresh:
                    candidates.append((score, tid, di))
        candidates.sort(key=lambda x: x[0], reverse=True)

        used_tracks, used_dets = set(), set()
        for _, tid, di in candidates:
            if tid in used_tracks or di in used_dets:
                continue
            matched_pairs.append((tid, di))
            used_tracks.add(tid)
            used_dets.add(di)

        # update matched tracks
        matched_results = []
        for tid, di in matched_pairs:
            det = detections[di]
            self._tracks[tid]["bbox"] = det["bbox"]
            self._tracks[tid]["missing"] = 0
            self._tracks[tid]["frames_seen"] += 1
            matched_results.append({
                **det,
                "track_id": tid,
                "frames_seen": self._tracks[tid]["frames_seen"],
            })

        # new tracks for unmatched detections
        new_results = []
        new_det_indices = set(range(len(detections))) - used_dets
        for di in new_det_indices:
            det = detections[di]
            tid = self._next_id
            self._next_id += 1
            self._tracks[tid] = {
                "bbox": det["bbox"],
                "missing": 0,
                "frames_seen": 1,
            }
            new_results.append({
                **det,
                "track_id": tid,
                "frames_seen": 1,
            })

        # age out unmatched tracks
        expired = []
        for tid in self._tracks:
            if tid not in used_tracks and tid not in {r["track_id"] for r in new_results}:
                self._tracks[tid]["missing"] += 1
                if self._tracks[tid]["missing"] > self._max_missing:
                    expired.append(tid)
        for tid in expired:
            del self._tracks[tid]

        return matched_results, new_results

    @property
    def active_count(self):
        return len(self._tracks)
