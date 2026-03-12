SEVERITY_LOW = "LOW"
SEVERITY_MEDIUM = "MEDIUM"
SEVERITY_HIGH = "HIGH"
SEVERITY_CRITICAL = "CRITICAL"

HMA_DENSITY = 2.4          # kg per liter (hot-mix asphalt ~2400 kg/m3)
TACK_COAT_RATE = 0.3       # liters per m2 (bitumen emulsion application rate)
AGGREGATE_DENSITY = 1600   # kg/m3 (granular base material)
BASE_REPAIR_DEPTH = 0.05   # meters — asphalt layer above aggregate

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


def classify_severity(area_m2: float, depth_m: float) -> str:
    if depth_m < 0.025 and area_m2 < 0.05:
        return SEVERITY_LOW
    if depth_m < 0.05 and area_m2 < 0.15:
        return SEVERITY_MEDIUM
    if depth_m < 0.1 and area_m2 < 0.3:
        return SEVERITY_HIGH
    return SEVERITY_CRITICAL


def estimate_materials(area_m2: float, depth_m: float, volume_liters: float) -> dict:
    hotmix_kg = round(volume_liters * HMA_DENSITY, 2)
    tack_coat_liters = round(area_m2 * TACK_COAT_RATE, 3)
    aggregate_base_kg = 0.0

    if depth_m > 0.1:
        aggregate_depth = depth_m - BASE_REPAIR_DEPTH
        aggregate_base_kg = round(aggregate_depth * area_m2 * AGGREGATE_DENSITY, 2)

    return {
        "hotmix_kg": hotmix_kg,
        "tack_coat_liters": tack_coat_liters,
        "aggregate_base_kg": aggregate_base_kg,
    }


def estimate_cost(materials: dict) -> float:
    cost = COST_LABOUR + COST_EQUIPMENT
    cost += materials["hotmix_kg"] * COST_HMA_PER_KG
    cost += materials["tack_coat_liters"] * COST_TACK_PER_LITER
    cost += materials["aggregate_base_kg"] * COST_AGGREGATE_PER_KG
    return round(cost, 2)


def estimate_repair(area_m2: float, depth_m: float, volume_m3: float, volume_liters: float) -> dict:
    severity = classify_severity(area_m2, depth_m)
    materials = estimate_materials(area_m2, depth_m, volume_liters)
    cost = estimate_cost(materials)

    return {
        "severity": severity,
        "repair_method": REPAIR_METHODS[severity],
        "materials": materials,
        "estimated_cost_inr": cost,
    }
