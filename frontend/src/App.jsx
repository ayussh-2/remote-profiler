import { useState, useEffect, useCallback } from "react";
import {
    Hexagon,
    Wifi,
    WifiOff,
    Activity,
    Radio,
    ScanLine,
} from "lucide-react";
import ControlPanel from "./components/ControlPanel";
import MapView from "./components/MapView";

import StreamView from "./components/StreamView";

const API_BASE = import.meta.env.VITE_API_BASE;

function StatsStrip({ logs }) {
    const totalVol = logs.reduce(
        (s, l) => s + (parseFloat(l.volume_liters) || 0),
        0,
    );
    const avgConf =
        logs.length > 0
            ? (logs.reduce((s, l) => s + Number(l.confidence), 0) /
                  logs.length) *
              100
            : 0;
    const avgDepth =
        logs.length > 0
            ? logs.reduce((s, l) => s + Number(l.depth_m), 0) / logs.length
            : 0;

    const items = [
        { label: "Total Detections", value: logs.length, unit: "" },
        { label: "Total Volume", value: totalVol.toFixed(2), unit: "L" },
        { label: "Avg Confidence", value: avgConf.toFixed(1), unit: "%" },
        { label: "Avg Depth", value: avgDepth.toFixed(3), unit: "m" },
    ];

    return (
        <div className="stats-strip">
            {items.map(({ label, value, unit }) => (
                <div key={label} className="stats-item">
                    <span
                        className="label label-sm"
                        style={{ marginBottom: 2 }}
                    >
                        {label}
                    </span>
                    <div className="stats-val">
                        {value}
                        {unit && <span className="stats-unit">{unit}</span>}
                    </div>
                </div>
            ))}
        </div>
    );
}

export default function App() {
    const [mode, setMode] = useState("manual");
    const [logs, setLogs] = useState([]);
    const [latest, setLatest] = useState(null);
    const [loading, setLoading] = useState(false);
    const [apiOk, setApiOk] = useState(false);
    const [selectedFile, setSelectedFile] = useState(null);
    const [imagePreview, setImagePreview] = useState(null);
    const [annotatedImg, setAnnotatedImg] = useState(null);
    const [depthMm, setDepthMm] = useState(80);
    const [lat, setLat] = useState("");
    const [lng, setLng] = useState("");
    const [error, setError] = useState(null);

    const fetchLogs = useCallback(() => {
        fetch(`${API_BASE}/logs`)
            .then((r) => r.json())
            .then((d) => {
                setApiOk(true);
                if (d.data) setLogs(d.data);
            })
            .catch(() => setApiOk(false));
    }, []);

    useEffect(() => {
        fetchLogs();
    }, [fetchLogs]);

    const handleFileChange = (file) => {
        setSelectedFile(file);
        setImagePreview(URL.createObjectURL(file));
        setAnnotatedImg(null);
        setLatest(null);
        setError(null);
    };

    const handleDetect = async () => {
        if (!selectedFile) {
            setError("Select an image first");
            return;
        }
        setLoading(true);
        setError(null);
        try {
            const body = new FormData();
            body.append("image", selectedFile);
            body.append("depth_mm", depthMm);
            body.append("lat", lat || 0);
            body.append("lng", lng || 0);

            const res = await fetch(`${API_BASE}/detect`, {
                method: "POST",
                body,
            });
            const data = await res.json();

            if (data.error) throw new Error(data.error);
            if (data.status === "no_defect" || data.status === "no_pothole") {
                setError("No defect detected in image");
            } else {
                setLatest(data);
                if (data.annotated_image)
                    setAnnotatedImg(
                        `data:image/jpeg;base64,${data.annotated_image}`,
                    );
                fetchLogs();
            }
        } catch (e) {
            setError(e.message);
        } finally {
            setLoading(false);
        }
    };

    const connectivity = apiOk ? "online" : "offline";

    return (
        <div className="app-root">
            {/* ── Header ── */}
            <header className="app-header">
                <Hexagon size={20} color="var(--accent)" strokeWidth={1.5} />
                <span className="header-logo">Pavement Profiler</span>
                <span className="header-sub">Road Defect Analysis System</span>
                <div className="header-right">
                    <div className="mode-toggle">
                        <button
                            className={`mode-btn ${mode === "manual" ? "mode-btn--active" : ""}`}
                            onClick={() => setMode("manual")}
                        >
                            <ScanLine size={11} />
                            Manual
                        </button>
                        <button
                            className={`mode-btn ${mode === "stream" ? "mode-btn--active" : ""}`}
                            onClick={() => setMode("stream")}
                        >
                            <Radio size={11} />
                            Live
                        </button>
                    </div>
                    {apiOk ? (
                        <Wifi size={13} color="var(--green)" />
                    ) : (
                        <WifiOff size={13} color="var(--muted)" />
                    )}
                    <span className={`status-text ${connectivity}`}>
                        {apiOk ? "ONLINE" : "OFFLINE"}
                    </span>
                    <div className={`status-dot ${connectivity}`} />
                </div>
            </header>

            {mode === "stream" ? (
                <StreamView />
            ) : (
                <>
                    <StatsStrip logs={logs} />

                    <div className="main-grid">
                        <div className="panel-bg">
                            <ControlPanel
                                imagePreview={imagePreview}
                                annotatedImg={annotatedImg}
                                depthMm={depthMm}
                                lat={lat}
                                lng={lng}
                                loading={loading}
                                error={error}
                                latest={latest}
                                logs={logs}
                                onFileChange={handleFileChange}
                                onDepthChange={setDepthMm}
                                onLatChange={setLat}
                                onLngChange={setLng}
                                onDetect={handleDetect}
                            />
                        </div>

                        <div className="right-stack">
                            <div className="map-panel">
                                <div className="map-panel-header">
                                    <Activity size={11} color="var(--muted)" />
                                    <span className="label label-inline">
                                        Defect Map
                                    </span>
                                    <span className="map-points">
                                        {
                                            logs.filter((l) => l.lat && l.lng)
                                                .length
                                        }{" "}
                                        POINTS
                                    </span>
                                </div>
                                <div className="map-inner">
                                    <MapView logs={logs} />
                                </div>
                            </div>

                            {/* <div className="logs-panel">
                                <LogsTable logs={logs} onRefresh={fetchLogs} />
                            </div> */}
                        </div>
                    </div>
                </>
            )}
        </div>
    );
}
