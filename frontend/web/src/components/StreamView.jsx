import { useEffect, useRef, useState, useCallback, useMemo } from "react";
import { io } from "socket.io-client";
import {
    Radio, Wifi, WifiOff, Clock, Zap, ChevronDown, ChevronUp,
    Square, RotateCcw, BarChart3, AlertTriangle,
} from "lucide-react";
import StatCard from "./StatCard";

const SEVERITY_BADGE = {
    LOW: "badge-green",
    MEDIUM: "badge-accent",
    HIGH: "badge-dim",
    CRITICAL: "badge-red",
};

const SEVERITY_RANK = { LOW: 0, MEDIUM: 1, HIGH: 2, CRITICAL: 3 };

const DEFECT_LABEL = {
    pothole: "POTHOLE",
    crack: "CRACK",
    shallow_pothole: "SHALLOW POTHOLE",
    unknown: "UNKNOWN",
};

const API_BASE = import.meta.env.VITE_API_BASE;
const SOCKET_URL = API_BASE ? API_BASE.replace("/api", "") : "http://localhost:5000";

const DEBOUNCE_MS = 2000;
const MAX_EVENTS = 50;

function timeAgo(ts) {
    const sec = Math.floor((Date.now() / 1000) - ts);
    if (sec < 5) return "just now";
    if (sec < 60) return `${sec}s ago`;
    if (sec < 3600) return `${Math.floor(sec / 60)}m ago`;
    return `${Math.floor(sec / 3600)}h ago`;
}

function summarizeTypes(detections) {
    const counts = {};
    for (const d of detections) {
        const label = DEFECT_LABEL[d.defect_type] || d.defect_type;
        counts[label] = (counts[label] || 0) + 1;
    }
    return Object.entries(counts).map(([t, c]) => `${c}x ${t}`).join(", ");
}

function worstSeverity(detections) {
    return detections.reduce(
        (worst, d) => (SEVERITY_RANK[d.severity] || 0) > (SEVERITY_RANK[worst] || 0) ? d.severity : worst,
        detections[0]?.severity || "LOW",
    );
}

function aggregateMaterials(detections) {
    const totals = {};
    for (const d of detections) {
        const mats = d.materials || {};
        for (const [k, v] of Object.entries(mats)) {
            if (typeof v === "number") totals[k] = (totals[k] || 0) + v;
        }
    }
    return totals;
}

const MAT_LABELS = {
    hotmix_kg: ["Hot-Mix", "kg"],
    tack_coat_liters: ["Tack Coat", "L"],
    aggregate_base_kg: ["Aggregate", "kg"],
    crack_sealant_liters: ["Sealant", "L"],
    primer_liters: ["Primer", "L"],
};

function PinnedTotals({ detections }) {
    if (detections.length < 2) return null;
    const totals = aggregateMaterials(detections);
    const entries = Object.entries(totals).filter(([k]) => MAT_LABELS[k]);
    if (entries.length === 0) return null;

    return (
        <div className="stream-totals">
            <span className="label">Total Materials (all {detections.length} defects)</span>
            <div className="detection-grid">
                {entries.map(([k, v]) => (
                    <StatCard key={k} label={MAT_LABELS[k][0]} value={v} unit={MAT_LABELS[k][1]} size="sm" />
                ))}
            </div>
        </div>
    );
}

function MaterialsByType({ detections }) {
    const grouped = useMemo(() => {
        const m = {};
        for (const d of detections) {
            const t = d.defect_type || "unknown";
            if (!m[t]) m[t] = [];
            m[t].push(d);
        }
        return m;
    }, [detections]);

    const types = Object.keys(grouped);
    if (types.length < 2) return null;

    return (
        <div className="summary-section">
            <span className="summary-section-label">Materials by Defect Type</span>
            <div className="summary-type-cards">
                {types.map((type) => {
                    const dets = grouped[type];
                    const mats = aggregateMaterials(dets);
                    const entries = Object.entries(mats).filter(([k]) => MAT_LABELS[k]);
                    return (
                        <div key={type} className="summary-type-card">
                            <div className="summary-type-card-header">
                                <span className="badge badge-dim">
                                    {(DEFECT_LABEL[type] || type).toUpperCase()}
                                </span>
                                <span className="stream-meta">{dets.length} defect{dets.length !== 1 ? "s" : ""}</span>
                            </div>
                            <div className="detection-grid">
                                {entries.map(([k, v]) => (
                                    <StatCard key={k} label={MAT_LABELS[k][0]} value={v.toFixed(3)} unit={MAT_LABELS[k][1]} size="sm" />
                                ))}
                            </div>
                        </div>
                    );
                })}
            </div>
        </div>
    );
}

function formatDuration(ms) {
    const s = Math.floor(ms / 1000);
    const m = Math.floor(s / 60);
    const h = Math.floor(m / 60);
    if (h > 0) return `${h}h ${m % 60}m ${s % 60}s`;
    if (m > 0) return `${m}m ${s % 60}s`;
    return `${s}s`;
}

function SessionSummary({ events, sessionStart, onResume }) {
    const allDets = useMemo(
        () => events.flatMap((e) => e.detections),
        [events],
    );

    const duration = useMemo(() => Date.now() - sessionStart, [sessionStart]);

    const typeCounts = useMemo(() => {
        const m = {};
        for (const d of allDets) {
            const t = d.defect_type || "unknown";
            m[t] = (m[t] || 0) + 1;
        }
        return m;
    }, [allDets]);

    const sevCounts = useMemo(() => {
        const m = { LOW: 0, MEDIUM: 0, HIGH: 0, CRITICAL: 0 };
        for (const d of allDets) m[d.severity] = (m[d.severity] || 0) + 1;
        return m;
    }, [allDets]);

    const totals = useMemo(() => {
        let area = 0, depth = 0, vol = 0, conf = 0;
        for (const d of allDets) {
            area += d.area_m2 || 0;
            depth += d.depth_m || 0;
            vol += d.volume_liters || 0;
            conf += d.confidence || 0;
        }
        const n = allDets.length || 1;
        return { area, avgDepth: depth / n, vol, avgConf: conf / n };
    }, [allDets]);

    const matTotals = useMemo(() => aggregateMaterials(allDets), [allDets]);
    const matEntries = Object.entries(matTotals).filter(([k]) => MAT_LABELS[k]);

    const repairMethods = useMemo(() => {
        const m = {};
        for (const d of allDets) {
            const rm = d.repair_method || "Unknown";
            m[rm] = (m[rm] || 0) + 1;
        }
        return Object.entries(m).sort((a, b) => b[1] - a[1]);
    }, [allDets]);

    if (events.length === 0) {
        return (
            <div className="summary-overlay">
                <div className="summary-empty">
                    <Radio size={40} color="var(--muted)" />
                    <span>No defects were detected during this session.</span>
                    <button className="btn btn-primary" onClick={onResume}>
                        <RotateCcw size={12} /> Resume Stream
                    </button>
                </div>
            </div>
        );
    }

    return (
        <div className="summary-overlay">
            <div className="summary-scroll">
                <div className="summary-header">
                    <BarChart3 size={18} color="var(--accent)" />
                    <span className="summary-title">Session Summary</span>
                    <button className="btn btn-primary btn-sm" onClick={onResume}>
                        <RotateCcw size={11} /> New Session
                    </button>
                </div>

                {/* top stats row */}
                <div className="summary-stats-row">
                    <StatCard label="Total Defects" value={allDets.length} />
                    <StatCard label="Events" value={events.length} />
                    <StatCard label="Duration" value={formatDuration(duration)} />
                    <StatCard label="Avg Confidence" value={`${(totals.avgConf * 100).toFixed(1)}%`} />
                </div>

                {/* measurements */}
                <div className="summary-section">
                    <span className="summary-section-label">Measurements</span>
                    <div className="summary-stats-row">
                        <StatCard label="Total Area" value={totals.area.toFixed(4)} unit="m2" />
                        <StatCard label="Avg Depth" value={totals.avgDepth.toFixed(4)} unit="m" />
                        <StatCard label="Total Volume" value={totals.vol.toFixed(4)} unit="L" />
                    </div>
                </div>

                <div className="summary-columns">
                    {/* type breakdown */}
                    <div className="summary-section">
                        <span className="summary-section-label">Defect Types</span>
                        <div className="summary-breakdown">
                            {Object.entries(typeCounts).map(([type, count]) => (
                                <div key={type} className="summary-bar-row">
                                    <span className="badge badge-dim">
                                        {(DEFECT_LABEL[type] || type).toUpperCase()}
                                    </span>
                                    <div className="summary-bar-track">
                                        <div
                                            className="summary-bar-fill summary-bar-fill--type"
                                            style={{ width: `${(count / allDets.length) * 100}%` }}
                                        />
                                    </div>
                                    <span className="summary-bar-val">{count}</span>
                                </div>
                            ))}
                        </div>
                    </div>

                    {/* severity breakdown */}
                    <div className="summary-section">
                        <span className="summary-section-label">Severity Distribution</span>
                        <div className="summary-breakdown">
                            {["LOW", "MEDIUM", "HIGH", "CRITICAL"].filter((s) => sevCounts[s] > 0).map((sev) => (
                                <div key={sev} className="summary-bar-row">
                                    <span className={`badge ${SEVERITY_BADGE[sev]}`}>{sev}</span>
                                    <div className="summary-bar-track">
                                        <div
                                            className={`summary-bar-fill summary-bar-fill--${sev.toLowerCase()}`}
                                            style={{ width: `${(sevCounts[sev] / allDets.length) * 100}%` }}
                                        />
                                    </div>
                                    <span className="summary-bar-val">{sevCounts[sev]}</span>
                                </div>
                            ))}
                        </div>
                    </div>
                </div>

                {/* repair methods */}
                <div className="summary-section">
                    <span className="summary-section-label">Repair Methods Required</span>
                    <div className="summary-breakdown">
                        {repairMethods.map(([method, count]) => (
                            <div key={method} className="summary-bar-row">
                                <AlertTriangle size={10} color="var(--accent)" />
                                <span className="summary-method-name">{method}</span>
                                <span className="summary-bar-val">{count}x</span>
                            </div>
                        ))}
                    </div>
                </div>

                {/* materials per defect type */}
                <MaterialsByType detections={allDets} />

                {/* grand total materials */}
                {matEntries.length > 0 && (
                    <div className="summary-section summary-section--highlight">
                        <span className="summary-section-label">Grand Total -- All Materials</span>
                        <div className="summary-stats-row">
                            {matEntries.map(([k, v]) => (
                                <StatCard
                                    key={k}
                                    label={MAT_LABELS[k][0]}
                                    value={v.toFixed(3)}
                                    unit={MAT_LABELS[k][1]}
                                />
                            ))}
                        </div>
                    </div>
                )}

                {/* full detection ledger */}
                <div className="summary-section">
                    <span className="summary-section-label">
                        Detection Ledger ({allDets.length} defects across {events.length} events)
                    </span>
                    <div className="summary-table-wrap">
                        <table className="summary-table">
                            <thead>
                                <tr>
                                    <th>#</th>
                                    <th>Time</th>
                                    <th>Type</th>
                                    <th>Severity</th>
                                    <th>Conf</th>
                                    <th>Area (m2)</th>
                                    <th>Depth (m)</th>
                                    <th>Vol (L)</th>
                                    <th>Repair Method</th>
                                    <th>Materials</th>
                                </tr>
                            </thead>
                            <tbody>
                                {(() => {
                                    let idx = 0;
                                    return events.map((evt) =>
                                        evt.detections.map((d) => {
                                            idx += 1;
                                            const ts = new Date(evt.timestamp * 1000);
                                            const time = ts.toLocaleTimeString();
                                            const mats = d.materials || {};
                                            const matStr = Object.entries(mats)
                                                .filter(([k]) => MAT_LABELS[k])
                                                .map(([k, v]) => `${MAT_LABELS[k][0]}: ${v.toFixed(3)} ${MAT_LABELS[k][1]}`)
                                                .join(", ");
                                            return (
                                                <tr key={`${evt.id}-${idx}`} className={idx % 2 === 0 ? "row-alt" : ""}>
                                                    <td>{idx}</td>
                                                    <td>{time}</td>
                                                    <td>
                                                        <span className="badge badge-dim">
                                                            {(DEFECT_LABEL[d.defect_type] || d.defect_type || "").toUpperCase()}
                                                        </span>
                                                    </td>
                                                    <td>
                                                        <span className={`badge ${SEVERITY_BADGE[d.severity] || "badge-accent"}`}>
                                                            {d.severity}
                                                        </span>
                                                    </td>
                                                    <td>{((d.confidence || 0) * 100).toFixed(0)}%</td>
                                                    <td>{d.area_m2?.toFixed(6) ?? "--"}</td>
                                                    <td>{d.depth_m?.toFixed(4) ?? "--"}</td>
                                                    <td>{d.volume_liters?.toFixed(4) ?? "--"}</td>
                                                    <td className="summary-td-method">{d.repair_method || "--"}</td>
                                                    <td className="summary-td-mats">{matStr || "--"}</td>
                                                </tr>
                                            );
                                        })
                                    );
                                })()}
                            </tbody>
                        </table>
                    </div>
                </div>

                {/* event snapshot gallery */}
                <div className="summary-section">
                    <span className="summary-section-label">
                        Event Snapshots ({events.length})
                    </span>
                    <div className="summary-event-grid">
                        {events.map((evt) => {
                            const evtWorst = worstSeverity(evt.detections);
                            const ts = new Date(evt.timestamp * 1000).toLocaleTimeString();
                            return (
                                <div key={evt.id} className="summary-event-card">
                                    <img src={evt.snapshot} alt="" className="summary-event-img" />
                                    <div className="summary-event-meta">
                                        <span className={`badge ${SEVERITY_BADGE[evtWorst]}`}>{evtWorst}</span>
                                        <span className="stream-event-type">
                                            {evt.count > 1
                                                ? `${evt.count} defects`
                                                : DEFECT_LABEL[evt.detections[0]?.defect_type] || "?"}
                                        </span>
                                        <span className="stream-meta">{ts}</span>
                                    </div>
                                </div>
                            );
                        })}
                    </div>
                </div>
            </div>
        </div>
    );
}

export default function StreamView() {
    const [connected, setConnected] = useState(false);
    const [receiving, setReceiving] = useState(false);
    const [showSummary, setShowSummary] = useState(false);
    const [fps, setFps] = useState(0);
    const [viewerCount, setViewerCount] = useState(0);
    const [frameSrc, setFrameSrc] = useState(null);
    const [flash, setFlash] = useState(false);
    const [events, setEvents] = useState([]);
    const [pinnedEvent, setPinnedEvent] = useState(null);
    const [expandedDet, setExpandedDet] = useState(null);
    const [, setTick] = useState(0);

    const socketRef = useRef(null);
    const frameCountRef = useRef(0);
    const detCountRef = useRef(0);
    const lastEventTimeRef = useRef(0);
    const lastFrameTimeRef = useRef(0);
    const sessionStartRef = useRef(0);
    const staleTimerRef = useRef(null);
    const timerRef = useRef(null);

    useEffect(() => {
        timerRef.current = setInterval(() => {
            setTick((t) => t + 1);
            if (lastFrameTimeRef.current > 0 && Date.now() - lastFrameTimeRef.current > 3000) {
                setReceiving(false);
            }
        }, 1000);
        return () => clearInterval(timerRef.current);
    }, []);

    const addEvent = useCallback((detections, imageSrc) => {
        const now = Date.now() / 1000;
        if (now - lastEventTimeRef.current < DEBOUNCE_MS / 1000) return;
        lastEventTimeRef.current = now;

        const sorted = [...detections].sort((a, b) => b.confidence - a.confidence);
        detCountRef.current += 1;

        const evt = {
            id: detCountRef.current,
            timestamp: now,
            snapshot: imageSrc,
            detections: sorted,
            count: sorted.length,
        };

        setEvents((prev) => [evt, ...prev].slice(0, MAX_EVENTS));
        setPinnedEvent(evt);
        setExpandedDet(null);

        setFlash(true);
        setTimeout(() => setFlash(false), 400);
    }, []);

    const connect = useCallback(() => {
        if (socketRef.current?.connected) return;

        const socket = io(SOCKET_URL, {
            transports: ["websocket", "polling"],
            reconnection: true,
            reconnectionDelay: 1000,
        });

        socket.on("connect", () => setConnected(true));
        socket.on("disconnect", () => {
            setConnected(false);
            setReceiving(false);
        });

        socket.on("stream_frame", (data) => {
            const src = `data:image/jpeg;base64,${data.image}`;
            setFrameSrc(src);
            setFps(data.fps || 0);
            setReceiving(true);
            if (frameCountRef.current === 0) sessionStartRef.current = Date.now();
            frameCountRef.current += 1;
            lastFrameTimeRef.current = Date.now();

            const all = data.detections || [];
            if (all.length === 0) return;

            const hasTrackingInfo = all.some((d) => "is_new" in d);
            const eventDets = hasTrackingInfo
                ? all.filter((d) => d.is_new)
                : all;

            if (eventDets.length > 0) {
                addEvent(eventDets, src);
            }
        });

        socket.on("viewer_count", (data) => {
            setViewerCount(data.count || 0);
        });

        socketRef.current = socket;
    }, [addEvent]);

    useEffect(() => {
        connect();
        const timer = staleTimerRef.current;
        return () => {
            socketRef.current?.disconnect();
            clearTimeout(timer);
        };
    }, [connect]);

    const handleStop = () => setShowSummary(true);

    const handleResume = () => {
        setShowSummary(false);
        setEvents([]);
        setPinnedEvent(null);
        setExpandedDet(null);
        frameCountRef.current = 0;
        detCountRef.current = 0;
        lastEventTimeRef.current = 0;
        sessionStartRef.current = Date.now();
    };

    const dets = pinnedEvent?.detections || [];
    const worst = dets.length > 0 ? worstSeverity(dets) : null;

    if (showSummary) {
        return (
            <SessionSummary
                events={events}
                sessionStart={sessionStartRef.current}
                onResume={handleResume}
            />
        );
    }

    return (
        <div className="stream-root">
            <div className="stream-main">
                <div className={`stream-viewport ${flash ? "stream-viewport--flash" : ""}`}>
                    {frameSrc && receiving ? (
                        <img src={frameSrc} alt="live feed" className="stream-frame" />
                    ) : (
                        <div className="stream-placeholder">
                            <Radio size={40} color="var(--muted)" />
                            <span>
                                {connected
                                    ? "WAITING FOR ESP32 FEED..."
                                    : "CONNECTING TO SERVER..."}
                            </span>
                        </div>
                    )}

                    <div className="stream-hud stream-hud--top">
                        <div className="stream-hud-left">
                            <span className={`stream-badge ${receiving ? "stream-badge--live" : "stream-badge--idle"}`}>
                                {receiving ? "LIVE" : connected ? "WAITING" : "OFFLINE"}
                            </span>
                            {detCountRef.current > 0 && (
                                <span className="stream-badge stream-badge--count">
                                    {detCountRef.current} EVENT{detCountRef.current !== 1 ? "S" : ""}
                                </span>
                            )}
                        </div>
                        <div className="stream-hud-right">
                            <span className="stream-meta">{fps} FPS</span>
                            <span className="stream-meta">
                                {viewerCount} VIEWER{viewerCount !== 1 ? "S" : ""}
                            </span>
                            {connected ? (
                                <Wifi size={11} color="var(--green)" />
                            ) : (
                                <WifiOff size={11} color="var(--muted)" />
                            )}
                        </div>
                    </div>

                    {pinnedEvent && dets.length > 0 && (
                        <div className="stream-hud stream-hud--bottom">
                            <div className="stream-last-det">
                                <Zap size={10} />
                                <span className={`badge ${SEVERITY_BADGE[worst] || "badge-accent"}`}>
                                    {worst}
                                </span>
                                <span>{summarizeTypes(dets)}</span>
                                <span className="stream-meta stream-meta--dim">
                                    <Clock size={8} /> {timeAgo(pinnedEvent.timestamp)}
                                </span>
                            </div>
                        </div>
                    )}
                </div>

            </div>

            <aside className="stream-sidebar">
                {dets.length > 0 ? (
                    <div className="stream-pinned">
                        <span className="label">
                            Pinned Event -- {pinnedEvent.count} defect{pinnedEvent.count !== 1 ? "s" : ""}
                        </span>
                        <div className="stream-pinned-snap">
                            <img src={pinnedEvent.snapshot} alt="snapshot" />
                        </div>

                        <div className="stream-det-header">
                            <span className={`badge ${SEVERITY_BADGE[worst] || "badge-accent"}`}>
                                {worst}
                            </span>
                            <span className="stream-det-type">{summarizeTypes(dets)}</span>
                        </div>

                        <div className="stream-defect-list">
                            {dets.map((d, i) => {
                                const isOpen = expandedDet === i;
                                return (
                                    <div key={i} className="stream-defect-item">
                                        <button
                                            className="stream-defect-row"
                                            onClick={() => setExpandedDet(isOpen ? null : i)}
                                        >
                                            <span className="stream-defect-idx">#{i + 1}</span>
                                            <span className={`badge ${SEVERITY_BADGE[d.severity] || "badge-accent"}`}>
                                                {d.severity}
                                            </span>
                                            <span className="stream-defect-type">
                                                {DEFECT_LABEL[d.defect_type] || d.defect_type}
                                            </span>
                                            <span className="stream-meta" style={{ marginLeft: "auto" }}>
                                                {(d.confidence * 100).toFixed(0)}%
                                            </span>
                                            {isOpen
                                                ? <ChevronUp size={12} color="var(--muted)" />
                                                : <ChevronDown size={12} color="var(--muted)" />}
                                        </button>
                                        {isOpen && (
                                            <div className="stream-defect-detail">
                                                <div className="result-row">
                                                    <span className="label label-inline">Repair</span>
                                                    <span className="result-text">{d.repair_method}</span>
                                                </div>
                                                <div className="detection-grid">
                                                    <StatCard label="Area" value={d.area_m2} unit="m2" size="sm" />
                                                    <StatCard label="Depth" value={d.depth_m} unit="m" size="sm" />
                                                    <StatCard label="Volume" value={d.volume_liters} unit="L" size="sm" />
                                                </div>
                                                <div className="detection-grid">
                                                    {d.defect_type === "crack" ? (
                                                        <>
                                                            <StatCard label="Sealant" value={d.materials?.crack_sealant_liters ?? "--"} unit="L" size="sm" />
                                                            <StatCard label="Primer" value={d.materials?.primer_liters ?? "--"} unit="L" size="sm" />
                                                        </>
                                                    ) : (
                                                        <>
                                                            <StatCard label="Hot-Mix" value={d.materials?.hotmix_kg ?? "--"} unit="kg" size="sm" />
                                                            <StatCard label="Tack" value={d.materials?.tack_coat_liters ?? "--"} unit="L" size="sm" />
                                                            <StatCard label="Aggregate" value={d.materials?.aggregate_base_kg ?? "--"} unit="kg" size="sm" />
                                                        </>
                                                    )}
                                                </div>
                                            </div>
                                        )}
                                    </div>
                                );
                            })}
                        </div>

                        <PinnedTotals detections={dets} />
                    </div>
                ) : (
                    <div className="stream-no-det">NO DETECTIONS YET</div>
                )}

                <div className="stream-timeline">
                    <span className="label">
                        Detection Timeline ({events.length})
                    </span>
                    <div className="stream-events-scroll">
                        {events.length === 0 && (
                            <div className="stream-events-empty">
                                Events will appear here
                            </div>
                        )}
                        {events.map((evt) => {
                            const evtWorst = worstSeverity(evt.detections);
                            return (
                                <button
                                    key={evt.id}
                                    className={`stream-event-card ${pinnedEvent?.id === evt.id ? "stream-event-card--active" : ""}`}
                                    onClick={() => { setPinnedEvent(evt); setExpandedDet(null); }}
                                >
                                    <img src={evt.snapshot} alt="" className="stream-event-thumb" />
                                    <div className="stream-event-info">
                                        <div className="stream-event-top">
                                            <span className={`badge ${SEVERITY_BADGE[evtWorst] || "badge-accent"}`}>
                                                {evtWorst}
                                            </span>
                                            <span className="stream-event-type">
                                                {evt.count > 1
                                                    ? `${evt.count} defects`
                                                    : DEFECT_LABEL[evt.detections[0]?.defect_type] || "?"}
                                            </span>
                                        </div>
                                        <div className="stream-event-bottom">
                                            <span>{summarizeTypes(evt.detections)}</span>
                                            <span>{timeAgo(evt.timestamp)}</span>
                                        </div>
                                    </div>
                                </button>
                            );
                        })}
                    </div>
                </div>

                {events.length > 0 && (
                    <div className="stream-sidebar-footer">
                        <button className="stream-summary-btn" onClick={handleStop}>
                            <BarChart3 size={12} />
                            View Summary ({events.length} event{events.length !== 1 ? "s" : ""})
                        </button>
                    </div>
                )}
            </aside>
        </div>
    );
}
