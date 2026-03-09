import { useRef } from "react";
import { Upload, ScanLine, MapPin } from "lucide-react";
import StatCard from "./StatCard";

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
                {loading ? "Analyzing…" : "Run Detection"}
            </button>

            {/* ── Error ── */}
            {error && <div className="error-banner">✕ {error}</div>}

            {/* ── Latest result ── */}
            {latest && (
                <div>
                    <span className="label" style={{ marginTop: 4 }}>
                        Latest Detection
                    </span>
                    <div className="detection-grid">
                        <StatCard
                            label="Area"
                            value={latest.area_m2}
                            unit="m²"
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
