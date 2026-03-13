"""
Pothole volume estimation, material prediction, and cost estimation.

Volume calibration (MVP):
  Camera at ~30cm above road surface, 1px ~ 0.5mm.
  V = A * Z_max * 0.7 (bowl-shaped geometry correction, per IRC proposal)
"""

import numpy as np
from pathlib import Path

# --- Volume estimation constants ---
PX_TO_MM = 0.5
CORRECTION_FACTOR = 0.7

# --- Severity levels ---
SEVERITY_LOW = "LOW"
SEVERITY_MEDIUM = "MEDIUM"
SEVERITY_HIGH = "HIGH"
SEVERITY_CRITICAL = "CRITICAL"

# Material properties (IRC 15:2017, IS 2386)
HMA_DENSITY = 2.4
TACK_COAT_RATE = 0.3
AGGREGATE_DENSITY = 1600
BASE_REPAIR_DEPTH = 0.05

MATERIAL_MULTIPLIERS = {
    SEVERITY_LOW: {
        "hotmix_multiplier": 0.6,
        "tack_coat_multiplier": 0.8,
        "aggregate_multiplier": 0.0,
        "labour_multiplier": 0.5,
        "equipment_multiplier": 0.4,
    },
    SEVERITY_MEDIUM: {
        "hotmix_multiplier": 1.0,
        "tack_coat_multiplier": 1.0,
        "aggregate_multiplier": 0.3,
        "labour_multiplier": 1.0,
        "equipment_multiplier": 0.8,
    },
    SEVERITY_HIGH: {
        "hotmix_multiplier": 1.3,
        "tack_coat_multiplier": 1.2,
        "aggregate_multiplier": 0.7,
        "labour_multiplier": 1.3,
        "equipment_multiplier": 1.0,
    },
    SEVERITY_CRITICAL: {
        "hotmix_multiplier": 1.6,
        "tack_coat_multiplier": 1.5,
        "aggregate_multiplier": 1.0,
        "labour_multiplier": 1.6,
        "equipment_multiplier": 1.2,
    },
}

# Per-unit costs (INR)
COST_HMA_PER_KG = 7.0
COST_TACK_PER_LITER = 60.0
COST_AGGREGATE_PER_KG = 1.0
COST_LABOUR = 300
COST_EQUIPMENT = 150

REPAIR_METHODS = {
    SEVERITY_LOW: "Surface patch / slurry seal",
    SEVERITY_MEDIUM: "Throw-and-roll patch",
    SEVERITY_HIGH: "Full-depth semi-permanent patch",
    SEVERITY_CRITICAL: "Full-depth patch with base repair",
}


# --------------- Volume Estimation ---------------

def estimate_volume(area_px: float, depth_mm: float, confidence: float) -> dict:
    area_mm2 = area_px * (PX_TO_MM ** 2)
    area_m2 = area_mm2 / 1_000_000
    depth_m = depth_mm / 1000
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


# --------------- Severity & Materials ---------------

def classify_severity(area_m2: float, depth_m: float) -> str:
    if depth_m < 0.025 and area_m2 < 0.05:
        return SEVERITY_LOW
    if depth_m < 0.05 and area_m2 < 0.15:
        return SEVERITY_MEDIUM
    if depth_m < 0.1 and area_m2 < 0.3:
        return SEVERITY_HIGH
    return SEVERITY_CRITICAL


def estimate_materials(area_m2: float, depth_m: float, volume_liters: float, severity: str = None) -> dict:
    if severity is None:
        severity = classify_severity(area_m2, depth_m)

    multipliers = MATERIAL_MULTIPLIERS.get(severity, MATERIAL_MULTIPLIERS[SEVERITY_MEDIUM])

    hotmix_kg = round(volume_liters * HMA_DENSITY, 2)
    tack_coat_liters = round(area_m2 * TACK_COAT_RATE, 3)
    aggregate_base_kg = 0.0

    if depth_m > 0.1:
        aggregate_depth = depth_m - BASE_REPAIR_DEPTH
        aggregate_base_kg = round(aggregate_depth * area_m2 * AGGREGATE_DENSITY, 2)

    hotmix_kg = round(hotmix_kg * multipliers["hotmix_multiplier"], 2)
    tack_coat_liters = round(tack_coat_liters * multipliers["tack_coat_multiplier"], 3)
    aggregate_base_kg = round(aggregate_base_kg * multipliers["aggregate_multiplier"], 2)

    return {
        "hotmix_kg": hotmix_kg,
        "tack_coat_liters": tack_coat_liters,
        "aggregate_base_kg": aggregate_base_kg,
        "severity": severity,
    }


def estimate_cost(materials: dict, severity: str = None) -> float:
    if severity is None:
        severity = materials.get("severity", SEVERITY_MEDIUM)

    multipliers = MATERIAL_MULTIPLIERS.get(severity, MATERIAL_MULTIPLIERS[SEVERITY_MEDIUM])

    cost = (COST_LABOUR * multipliers["labour_multiplier"] +
            COST_EQUIPMENT * multipliers["equipment_multiplier"])
    cost += materials["hotmix_kg"] * COST_HMA_PER_KG
    cost += materials["tack_coat_liters"] * COST_TACK_PER_LITER
    cost += materials["aggregate_base_kg"] * COST_AGGREGATE_PER_KG
    return round(cost, 2)


def estimate_repair(area_m2: float, depth_m: float, volume_m3: float, volume_liters: float) -> dict:
    severity = classify_severity(area_m2, depth_m)
    materials = estimate_materials(area_m2, depth_m, volume_liters, severity)
    cost = estimate_cost(materials, severity)

    return {
        "severity": severity,
        "repair_method": REPAIR_METHODS[severity],
        "materials": materials,
        "estimated_cost_inr": cost,
    }


# --------------- ML Integration ---------------

_ml_models = {}
_ml_enabled = False


def enable_ml_mode(model_dir: str = 'backend/models/material_estimator') -> bool:
    global _ml_models, _ml_enabled

    try:
        import joblib

        model_dir_path = Path(model_dir)
        if not model_dir_path.exists():
            print(f"[ML] Models directory not found: {model_dir}")
            return False

        targets = ['hotmix_kg', 'tack_coat_liters', 'aggregate_base_kg']

        for target in targets:
            model_file = model_dir_path / f"material_{target}.pkl"
            scaler_file = model_dir_path / f"scaler_{target}.pkl"
            try:
                _ml_models[target] = {
                    'model': joblib.load(model_file),
                    'scaler': joblib.load(scaler_file),
                }
            except FileNotFoundError:
                print(f"[ML] Not found: {model_file}")
                return False

        _ml_enabled = True
        print("[ML] Models loaded successfully")
        return True

    except ImportError:
        print("[ML] joblib not installed -- cannot enable ML mode")
        return False
    except Exception as e:
        print(f"[ML] Failed to load models: {e}")
        return False


def predict_materials_ml(area_m2: float, depth_m: float, volume_liters: float) -> dict:
    if not _ml_enabled or not _ml_models:
        severity = classify_severity(area_m2, depth_m)
        materials = estimate_materials(area_m2, depth_m, volume_liters, severity)
        materials['prediction_source'] = 'RULE_BASED'
        return materials

    try:
        import pandas as pd
        features = pd.DataFrame(
            [[area_m2, depth_m, volume_liters]],
            columns=['area_m2', 'depth_m', 'volume_liters'],
        )

        predictions = {}
        for material, entry in _ml_models.items():
            scaled = entry['scaler'].transform(features)
            pred = entry['model'].predict(scaled)[0]
            predictions[material] = max(0, float(pred))

        return {
            "hotmix_kg": round(predictions['hotmix_kg'], 2),
            "tack_coat_liters": round(predictions['tack_coat_liters'], 3),
            "aggregate_base_kg": round(predictions['aggregate_base_kg'], 2),
            "severity": classify_severity(area_m2, depth_m),
            "prediction_source": "ML_MODEL",
        }

    except Exception as e:
        print(f"[ML] Prediction failed, falling back to rules: {e}")
        severity = classify_severity(area_m2, depth_m)
        materials = estimate_materials(area_m2, depth_m, volume_liters, severity)
        materials['prediction_source'] = 'RULE_BASED (ML failed)'
        return materials
