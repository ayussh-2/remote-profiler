import { useState, useEffect, useRef, useCallback } from "react";

const API_BASE = "http://localhost:5000/api";

// ─── Colour tokens ───────────────────────────────────────────────────────────
const C = {
  bg: "#0a0c0f",
  panel: "#10141a",
  border: "#1e2530",
  accent: "#f5a623",
  accentDim: "#b87a1a",
  red: "#e84040",
  green: "#2fd67a",
  text: "#e8ecf0",
  muted: "#5a6470",
};

// ─── Styles (inline, no Tailwind quirks) ─────────────────────────────────────
const S = {
  app: {
    minHeight: "100vh",
    background: C.bg,
    color: C.text,
    fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
    display: "flex",
    flexDirection: "column",
  },
  header: {
    borderBottom: `1px solid ${C.border}`,
    padding: "16px 28px",
    display: "flex",
    alignItems: "center",
    gap: 16,
    background: C.panel,
  },
  logo: {
    fontSize: 11,
    fontWeight: 700,
    letterSpacing: 4,
    color: C.accent,
    textTransform: "uppercase",
  },
  statusDot: (on) => ({
    width: 8,
    height: 8,
    borderRadius: "50%",
    background: on ? C.green : C.muted,
    boxShadow: on ? `0 0 8px ${C.green}` : "none",
    marginLeft: "auto",
  }),
  grid: {
    display: "grid",
    gridTemplateColumns: "340px 1fr",
    gridTemplateRows: "auto 1fr",
    gap: 1,
    flex: 1,
    background: C.border,
  },
  panel: {
    background: C.panel,
    padding: 20,
  },
  label: {
    fontSize: 9,
    letterSpacing: 3,
    color: C.muted,
    textTransform: "uppercase",
    marginBottom: 6,
  },
  statBox: {
    border: `1px solid ${C.border}`,
    borderRadius: 4,
    padding: "12px 14px",
    marginBottom: 10,
  },
  statVal: {
    fontSize: 24,
    fontWeight: 700,
    color: C.accent,
    lineHeight: 1,
  },
  statUnit: {
    fontSize: 11,
    color: C.muted,
    marginLeft: 4,
  },
  btn: (variant = "primary") => ({
    width: "100%",
    padding: "10px 0",
    borderRadius: 4,
    border: "none",
    cursor: "pointer",
    fontFamily: "inherit",
    fontSize: 11,
    letterSpacing: 2,
    fontWeight: 700,
    textTransform: "uppercase",
    background: variant === "primary" ? C.accent : "transparent",
    color: variant === "primary" ? "#000" : C.muted,
    borderColor: C.border,
    borderWidth: variant === "secondary" ? 1 : 0,
    borderStyle: "solid",
    marginBottom: 8,
    transition: "opacity 0.15s",
  }),
  imageBox: {
    width: "100%",
    aspectRatio: "16/9",
    background: "#070a0d",
    border: `1px solid ${C.border}`,
    borderRadius: 4,
    overflow: "hidden",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    marginBottom: 10,
    position: "relative",
  },
  table: {
    width: "100%",
    borderCollapse: "collapse",
    fontSize: 11,
  },
  th: {
    textAlign: "left",
    padding: "6px 10px",
    fontSize: 9,
    letterSpacing: 2,
    color: C.muted,
    borderBottom: `1px solid ${C.border}`,
    textTransform: "uppercase",
  },
  td: {
    padding: "8px 10px",
    borderBottom: `1px solid ${C.border}14`,
    fontVariantNumeric: "tabular-nums",
  },
  badge: (color) => ({
    display: "inline-block",
    padding: "2px 8px",
    borderRadius: 2,
    fontSize: 9,
    fontWeight: 700,
    letterSpacing: 2,
    textTransform: "uppercase",
    background: color + "22",
    color,
  }),
};

// ─── MapView (Leaflet via CDN) ────────────────────────────────────────────────
function MapView({ logs }) {
  const mapRef = useRef(null);
  const mapInstance = useRef(null);
  const markersRef = useRef([]);

  useEffect(() => {
    if (mapInstance.current) return;
    // Load Leaflet CSS
    if (!document.getElementById("leaflet-css")) {
      const link = document.createElement("link");
      link.id = "leaflet-css";
      link.rel = "stylesheet";
      link.href = "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css";
      document.head.appendChild(link);
    }
    // Load Leaflet JS
    const script = document.createElement("script");
    script.src = "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js";
    script.onload = () => {
      const L = window.L;
      mapInstance.current = L.map(mapRef.current, {
        center: [20.5937, 78.9629], // default: India center
        zoom: 5,
        zoomControl: true,
      });
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        attribution: "© OpenStreetMap",
      }).addTo(mapInstance.current);
    };
    document.head.appendChild(script);
  }, []);

  useEffect(() => {
    if (!mapInstance.current || !window.L) return;
    const L = window.L;
    // Clear old markers
    markersRef.current.forEach((m) => m.remove());
    markersRef.current = [];

    const validLogs = logs.filter((l) => l.lat && l.lng && (l.lat !== 0 || l.lng !== 0));
    validLogs.forEach((log) => {
      const icon = L.divIcon({
        className: "",
        html: `<div style="width:14px;height:14px;border-radius:50%;background:${C.accent};border:2px solid #000;box-shadow:0 0 8px ${C.accent}88"></div>`,
      });
      const marker = L.marker([log.lat, log.lng], { icon })
        .addTo(mapInstance.current)
        .bindPopup(
          `<b>Pothole</b><br>Depth: ${log.depth_m}m<br>Vol: ${log.volume_liters}L<br>Conf: ${(log.confidence * 100).toFixed(0)}%`
        );
      markersRef.current.push(marker);
    });

    if (validLogs.length > 0) {
      mapInstance.current.setView(
        [validLogs[validLogs.length - 1].lat, validLogs[validLogs.length - 1].lng],
        14
      );
    }
  }, [logs]);

  return (
    <div style={{ width: "100%", height: "100%", minHeight: 300, position: "relative" }}>
      <div ref={mapRef} style={{ width: "100%", height: "100%" }} />
      {logs.length === 0 && (
        <div
          style={{
            position: "absolute",
            inset: 0,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            background: "#0a0c0fcc",
            fontSize: 11,
            color: C.muted,
            letterSpacing: 2,
            pointerEvents: "none",
          }}
        >
          NO DATA — AWAITING SCAN
        </div>
      )}
    </div>
  );
}

// ─── Main App ────────────────────────────────────────────────────────────────
export default function App() {
  const [logs, setLogs] = useState([]);
  const [latest, setLatest] = useState(null);
  const [loading, setLoading] = useState(false);
  const [apiOk, setApiOk] = useState(false);
  const [imagePreview, setImagePreview] = useState(null);
  const [annotatedImg, setAnnotatedImg] = useState(null);
  const [depthMm, setDepthMm] = useState(80);
  const [lat, setLat] = useState("");
  const [lng, setLng] = useState("");
  const [error, setError] = useState(null);
  const fileRef = useRef();

  // Ping backend
  useEffect(() => {
    fetch(`${API_BASE}/logs`)
      .then((r) => r.json())
      .then((d) => {
        setApiOk(true);
        if (d.data) setLogs(d.data);
      })
      .catch(() => setApiOk(false));
  }, []);

  const fetchLogs = useCallback(() => {
    fetch(`${API_BASE}/logs`)
      .then((r) => r.json())
      .then((d) => d.data && setLogs(d.data))
      .catch(() => {});
  }, []);

  const handleFile = (e) => {
    const file = e.target.files[0];
    if (!file) return;
    const url = URL.createObjectURL(file);
    setImagePreview(url);
    setAnnotatedImg(null);
    setLatest(null);
    setError(null);
  };

  const handleDetect = async () => {
    if (!fileRef.current?.files[0]) {
      setError("Select an image first");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const formData = new FormData();
      formData.append("image", fileRef.current.files[0]);
      formData.append("depth_mm", depthMm);
      formData.append("lat", lat || 0);
      formData.append("lng", lng || 0);

      const res = await fetch(`${API_BASE}/detect`, { method: "POST", body: formData });
      const data = await res.json();

      if (data.error) throw new Error(data.error);
      if (data.status === "no_pothole") {
        setError("No pothole detected in image");
      } else {
        setLatest(data);
        if (data.annotated_image) {
          setAnnotatedImg(`data:image/jpeg;base64,${data.annotated_image}`);
        }
        fetchLogs();
      }
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  };

  const totalVol = logs.reduce((s, l) => s + (parseFloat(l.volume_liters) || 0), 0);

  return (
    <div style={S.app}>
      {/* ── Header ── */}
      <div style={S.header}>
        <div style={{ fontSize: 18, color: C.accent }}>⬡</div>
        <div style={S.logo}>Pavement Profiler</div>
        <div style={{ marginLeft: 16, fontSize: 10, color: C.muted, letterSpacing: 2 }}>
          MVP — ROAD DEFECT ANALYSIS SYSTEM
        </div>
        <div style={S.statusDot(apiOk)} title={apiOk ? "API connected" : "API offline"} />
        <div style={{ fontSize: 9, color: apiOk ? C.green : C.red, letterSpacing: 2 }}>
          {apiOk ? "ONLINE" : "OFFLINE"}
        </div>
      </div>

      {/* ── Main Grid ── */}
      <div style={S.grid}>
        {/* ── Left: Control Panel ── */}
        <div style={{ ...S.panel, gridRow: "1 / 3", display: "flex", flexDirection: "column", gap: 0 }}>
          <div style={S.label}>Input</div>

          {/* Image preview */}
          <div style={S.imageBox}>
            {annotatedImg || imagePreview ? (
              <img
                src={annotatedImg || imagePreview}
                alt="preview"
                style={{ width: "100%", height: "100%", objectFit: "contain" }}
              />
            ) : (
              <span style={{ fontSize: 10, color: C.muted, letterSpacing: 2 }}>NO IMAGE LOADED</span>
            )}
            {annotatedImg && (
              <div style={{ position: "absolute", top: 6, right: 6, ...S.badge(C.green) }}>
                ANNOTATED
              </div>
            )}
          </div>

          <input
            ref={fileRef}
            type="file"
            accept="image/*"
            onChange={handleFile}
            style={{ display: "none" }}
            id="file-input"
          />
          <label htmlFor="file-input" style={{ ...S.btn("secondary"), textAlign: "center", display: "block", padding: "10px 0", cursor: "pointer" }}>
            Select Image
          </label>

          {/* Depth input */}
          <div style={S.label}>ToF Depth (mm)</div>
          <input
            type="number"
            value={depthMm}
            onChange={(e) => setDepthMm(e.target.value)}
            style={{
              width: "100%",
              padding: "8px 10px",
              background: C.bg,
              border: `1px solid ${C.border}`,
              borderRadius: 4,
              color: C.text,
              fontFamily: "inherit",
              fontSize: 14,
              marginBottom: 10,
              boxSizing: "border-box",
            }}
          />

          {/* GPS coords */}
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8, marginBottom: 10 }}>
            {[["Latitude", lat, setLat], ["Longitude", lng, setLng]].map(([lbl, val, set]) => (
              <div key={lbl}>
                <div style={S.label}>{lbl}</div>
                <input
                  type="number"
                  value={val}
                  placeholder="0.000"
                  onChange={(e) => set(e.target.value)}
                  style={{
                    width: "100%",
                    padding: "6px 8px",
                    background: C.bg,
                    border: `1px solid ${C.border}`,
                    borderRadius: 4,
                    color: C.text,
                    fontFamily: "inherit",
                    fontSize: 12,
                    boxSizing: "border-box",
                  }}
                />
              </div>
            ))}
          </div>

          <button style={S.btn("primary")} onClick={handleDetect} disabled={loading}>
            {loading ? "Analyzing…" : "Run Detection"}
          </button>

          {error && (
            <div style={{ fontSize: 10, color: C.red, letterSpacing: 1, marginBottom: 8 }}>
              ✕ {error}
            </div>
          )}

          {/* Latest result stats */}
          {latest && (
            <>
              <div style={{ ...S.label, marginTop: 12 }}>Latest Detection</div>
              {[
                ["Area", `${latest.area_m2} m²`],
                ["Depth", `${latest.depth_m} m`],
                ["Volume", `${latest.volume_liters} L`],
                ["Confidence", `${(latest.confidence * 100).toFixed(1)} %`],
              ].map(([k, v]) => (
                <div key={k} style={S.statBox}>
                  <div style={S.label}>{k}</div>
                  <div style={S.statVal}>{v}</div>
                </div>
              ))}
            </>
          )}

          {/* Summary stats */}
          <div style={{ marginTop: "auto", paddingTop: 16 }}>
            <div style={S.label}>Session Summary</div>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8 }}>
              <div style={S.statBox}>
                <div style={S.label}>Scanned</div>
                <div style={{ ...S.statVal, fontSize: 18 }}>{logs.length}</div>
              </div>
              <div style={S.statBox}>
                <div style={S.label}>Total Vol</div>
                <div style={{ ...S.statVal, fontSize: 18 }}>{totalVol.toFixed(2)}<span style={S.statUnit}>L</span></div>
              </div>
            </div>
          </div>
        </div>

        {/* ── Top-right: Map ── */}
        <div style={{ ...S.panel, height: 320 }}>
          <div style={S.label}>Defect Map</div>
          <div style={{ height: "calc(100% - 20px)", borderRadius: 4, overflow: "hidden", border: `1px solid ${C.border}` }}>
            <MapView logs={logs} />
          </div>
        </div>

        {/* ── Bottom-right: Logs table ── */}
        <div style={{ ...S.panel, overflowY: "auto" }}>
          <div style={{ display: "flex", alignItems: "center", marginBottom: 12 }}>
            <div style={S.label}>Detection Log</div>
            <button
              onClick={fetchLogs}
              style={{ marginLeft: "auto", background: "none", border: "none", color: C.muted, cursor: "pointer", fontSize: 10, fontFamily: "inherit", letterSpacing: 2 }}
            >
              ↻ REFRESH
            </button>
          </div>
          {logs.length === 0 ? (
            <div style={{ fontSize: 10, color: C.muted, letterSpacing: 2, textAlign: "center", paddingTop: 40 }}>
              NO DETECTIONS LOGGED
            </div>
          ) : (
            <table style={S.table}>
              <thead>
                <tr>
                  {["Time", "Lat", "Lng", "Area m²", "Depth m", "Vol L", "Conf"].map((h) => (
                    <th key={h} style={S.th}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {[...logs].reverse().map((log, i) => (
                  <tr key={i} style={{ background: i % 2 === 0 ? "#ffffff04" : "transparent" }}>
                    <td style={S.td}>{log.datetime || log.timestamp}</td>
                    <td style={S.td}>{Number(log.lat).toFixed(4)}</td>
                    <td style={S.td}>{Number(log.lng).toFixed(4)}</td>
                    <td style={S.td}>{log.area_m2}</td>
                    <td style={S.td}>{log.depth_m}</td>
                    <td style={S.td}>
                      <span style={S.badge(C.accent)}>{log.volume_liters}</span>
                    </td>
                    <td style={S.td}>
                      <span style={S.badge(Number(log.confidence) > 0.7 ? C.green : C.accentDim)}>
                        {(Number(log.confidence) * 100).toFixed(0)}%
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </div>
  );
}
