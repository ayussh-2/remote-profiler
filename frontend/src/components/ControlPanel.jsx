import { useRef } from "react";
import { Upload, ScanLine, MapPin } from "lucide-react";
import StatCard from "./StatCard";

const SEVERITY_BADGE = {
    LOW: "badge-green",
    MEDIUM: "badge-accent",
    HIGH: "badge-dim",
    CRITICAL: "badge-red",
};

const DEFECT_LABEL = {
    pothole: "POTHOLE",
    crack: "CRACK",
    shallow_pothole: "SHALLOW POTHOLE",
};

export default function ControlPanel({
    imagePreview,
    annotatedImg,
    depthMm,
    lat,
    lng,
    loading,
    error,
    latest,
    logs,
    onFileChange,
    onDepthChange,
    onLatChange,
    onLngChange,
    onDetect,
}) {
    const fileRef = useRef();
    const totalVol = logs.reduce(
        (s, l) => s + (parseFloat(l.volume_liters) || 0),
        0,
    );

    return (
        <aside className="control-aside">
            {/* ── Image preview ── */}
            <div>
                <span className="label">Preview</span>
                <div className="preview-box">
                    {annotatedImg || imagePreview ? (
                        <img
                            src={annotatedImg || imagePreview}
                            alt="preview"
                            className="preview-img"
                        />
                    ) : (
                        <span className="preview-placeholder">
                            NO IMAGE LOADED
                        </span>
                    )}
                    {annotatedImg && (
                        <span className="badge badge-green badge-overlay">
                            ANNOTATED
                        </span>
                    )}
                </div>

                <input
                    ref={fileRef}
                    type="file"
                    accept="image/*"
                    onChange={(e) => {
                        const f = e.target.files[0];
                        if (f) onFileChange(f);
                    }}
                    style={{ display: "none" }}
                    id="file-input"
                />
                <label htmlFor="file-input" className="btn btn-secondary">
                    <Upload size={12} />
                    Select Image
                </label>
            </div>

            {/* ── Depth input ── */}
            <div>
                <span className="label">ToF Depth (mm)</span>
                <input
                    type="number"
                    value={depthMm}
                    onChange={(e) => onDepthChange(e.target.value)}
                    className="input-field"
                />
            </div>

            {/* ── GPS coords ── */}
            <div>
                <span className="label label-icon">
                    <MapPin size={10} />
                    GPS Coordinates
                </span>
                <div className="gps-grid">
                    {[
                        ["Lat", lat, onLatChange],
                        ["Lng", lng, onLngChange],
                    ].map(([lbl, val, setter]) => (
                        <div key={lbl}>
                            <span className="label label-sm">{lbl}</span>
                            <input
                                type="number"
                                value={val}
                                placeholder="0.0000"
                                onChange={(e) => setter(e.target.value)}
                                className="input-field sm"
                            />
                        </div>
                    ))}
                </div>
            </div>

            {/* ── Run Detection ── */}
            <button
                className="btn btn-primary"
                onClick={onDetect}
                disabled={loading}
            >
                <ScanLine size={14} />
                {loading ? "Analyzing..." : "Run Detection"}
            </button>

            {/* ── Error ── */}
            {error && <div className="error-banner">x {error}</div>}

            {/* ── Latest result ── */}
            {latest && (
                <>
                    <div>
                        <span className="label" style={{ marginTop: 4 }}>
                            Latest Detection
                        </span>
                        <div className="detection-grid">
                            <StatCard
                                label="Area"
                                value={latest.area_m2}
                                unit="m2"
                                size="sm"
                            />
                            <StatCard
                                label="Depth"
                                value={latest.depth_m}
                                unit="m"
                                size="sm"
                            />
                            <StatCard
                                label="Volume"
                                value={latest.volume_liters}
                                unit="L"
                                size="sm"
                            />
                            <StatCard
                                label="Conf"
                                value={`${(latest.confidence * 100).toFixed(1)}%`}
                                size="sm"
                            />
                        </div>
                    </div>

                    {/* ── Severity & Repair ── */}
                    <div className="result-section">
                        {latest.defect_type && (
                            <div className="result-row">
                                <span className="label label-inline">Type</span>
                                <span className="badge badge-accent">
                                    {DEFECT_LABEL[latest.defect_type] || latest.defect_type}
                                </span>
                            </div>
                        )}
                        <div className="result-row">
                            <span className="label label-inline">Severity</span>
                            <span className={`badge ${SEVERITY_BADGE[latest.severity] || "badge-accent"}`}>
                                {latest.severity}
                            </span>
                        </div>
                        <div className="result-row">
                            <span className="label label-inline">Repair</span>
                            <span className="result-text">{latest.repair_method}</span>
                        </div>
                        <div className="result-row">
                            <span className="label label-inline">Source</span>
                            <span className="result-text result-text--dim">
                                {latest.prediction_source}
                            </span>
                        </div>
                    </div>

                    {/* ── Materials ── */}
                    <div>
                        <span className="label">Materials Required</span>
                        <div className="detection-grid">
                            {latest.defect_type === "crack" ? (
                                <>
                                    <StatCard
                                        label="Crack Sealant"
                                        value={latest.materials?.crack_sealant_liters ?? "--"}
                                        unit="L"
                                        size="sm"
                                    />
                                    <StatCard
                                        label="Primer"
                                        value={latest.materials?.primer_liters ?? "--"}
                                        unit="L"
                                        size="sm"
                                    />
                                </>
                            ) : (
                                <>
                                    <StatCard
                                        label="Hot-Mix Asphalt"
                                        value={latest.materials?.hotmix_kg ?? "--"}
                                        unit="kg"
                                        size="sm"
                                    />
                                    <StatCard
                                        label="Tack Coat"
                                        value={latest.materials?.tack_coat_liters ?? "--"}
                                        unit="L"
                                        size="sm"
                                    />
                                    <StatCard
                                        label="Aggregate Base"
                                        value={latest.materials?.aggregate_base_kg ?? "--"}
                                        unit="kg"
                                        size="sm"
                                    />
                                </>
                            )}
                        </div>
                    </div>
                </>
            )}

            {/* ── Session summary ── */}
            <div className="session-section">
                <span className="label">Session Summary</span>
                <div className="detection-grid">
                    <StatCard label="Scanned" value={logs.length} size="sm" />
                    <StatCard
                        label="Total Vol"
                        value={totalVol.toFixed(2)}
                        unit="L"
                        size="sm"
                    />
                </div>
            </div>
        </aside>
    );
}
