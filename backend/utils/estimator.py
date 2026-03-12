"""
Volume estimation from detected pothole area (pixels) and ToF depth.

Calibration assumption (MVP):
  - Camera mounted at ~30cm above road surface
  - At 30cm height, 1 pixel ≈ 0.5mm (adjust PX_TO_MM per your setup)
  - Fine-tune PX_TO_MM by measuring a known object at deployment height

Formula:
  V = A * Z_max * 0.7
  where:
    A   = surface area in m²  (from pixel area + calibration)
    Z   = depth in meters     (from ToF sensor)
    0.7 = correction factor for bowl-shaped geometry (from proposal)
"""

# --- Calibration constants (adjust per hardware setup) ---
PX_TO_MM = 0.5          # mm per pixel at camera mount height (~30cm)
CORRECTION_FACTOR = 0.7  # accounts for sloped bowl geometry


def estimate_volume(area_px: float, depth_mm: float, confidence: float) -> dict:
    """
    Convert pixel area + depth in mm → volume in m³ and liters.
    """
    # Area: px² → mm² → m²
    area_mm2 = area_px * (PX_TO_MM ** 2)
    area_m2 = area_mm2 / 1_000_000

    # Depth: mm → m
    depth_m = depth_mm / 1000

    # Volume estimation
    volume_m3 = area_m2 * depth_m * CORRECTION_FACTOR
    volume_liters = volume_m3 * 1000

    return {
        "area_m2": round(area_m2, 6),
        "depth_m": round(depth_m, 4),
        "volume_m3": round(volume_m3, 8),
        "volume_liters": round(volume_liters, 4),
        "volume_min_liters": round(volume_liters * 0.8, 4),
        "volume_max_liters": round(volume_liters * 1.2, 4),
    }
