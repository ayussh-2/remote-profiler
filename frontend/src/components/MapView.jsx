import { useEffect } from "react";
import { MapContainer, TileLayer, Marker, Popup, useMap } from "react-leaflet";
import L from "leaflet";
import "leaflet/dist/leaflet.css";

// Fix default marker icon paths broken by bundlers
delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
    iconRetinaUrl: new URL(
        "leaflet/dist/images/marker-icon-2x.png",
        import.meta.url,
    ).href,
    iconUrl: new URL("leaflet/dist/images/marker-icon.png", import.meta.url)
        .href,
    shadowUrl: new URL("leaflet/dist/images/marker-shadow.png", import.meta.url)
        .href,
});

const dotIcon = L.divIcon({
    className: "",
    html: `<div style="width:14px;height:14px;border-radius:50%;background:var(--accent);border:2px solid #000;box-shadow:0 0 10px var(--accent)"></div>`,
    iconAnchor: [7, 7],
});

function FlyTo({ logs }) {
    const map = useMap();
    useEffect(() => {
        const valid = logs.filter(
            (l) => l.lat && l.lng && (l.lat !== 0 || l.lng !== 0),
        );
        if (valid.length > 0) {
            const last = valid[valid.length - 1];
            map.flyTo([last.lat, last.lng], 14, { duration: 1 });
        }
    }, [logs, map]);
    return null;
}

export default function MapView({ logs }) {
    const validLogs = logs.filter(
        (l) => l.lat && l.lng && (l.lat !== 0 || l.lng !== 0),
    );

    return (
        <div className="map-root">
            <MapContainer
                center={[20.5937, 78.9629]}
                zoom={5}
                style={{ width: "100%", height: "100%" }}
                zoomControl
            >
                <TileLayer
                    url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                    attribution="© OpenStreetMap"
                />
                {validLogs.map((log, i) => (
                    <Marker
                        key={i}
                        position={[log.lat, log.lng]}
                        icon={dotIcon}
                    >
                        <Popup>
                            <b>Pothole #{i + 1}</b>
                            <br />
                            Depth: {log.depth_m} m<br />
                            Vol: {log.volume_liters} L<br />
                            Conf: {(log.confidence * 100).toFixed(0)}%
                        </Popup>
                    </Marker>
                ))}
                <FlyTo logs={logs} />
            </MapContainer>

            {validLogs.length === 0 && (
                <div className="map-no-data">NO DATA — AWAITING SCAN</div>
            )}
        </div>
    );
}
