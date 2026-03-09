import { RefreshCw } from "lucide-react";

const COLS = ["Time", "Lat", "Lng", "Area m²", "Depth m", "Vol L", "Conf"];

function confidenceBadgeClass(conf) {
    const n = Number(conf);
    if (n >= 0.75) return "badge badge-green";
    if (n >= 0.5) return "badge badge-accent";
    return "badge badge-red";
}

export default function LogsTable({ logs, onRefresh }) {
    return (
        <div className="logs-wrapper">
            {/* toolbar */}
            <div className="logs-toolbar">
                <span className="label label-inline">Detection Log</span>
                <button
                    onClick={onRefresh}
                    title="Refresh"
                    className="refresh-btn"
                >
                    <RefreshCw size={12} />
                    REFRESH
                </button>
            </div>

            {/* table / empty state */}
            {logs.length === 0 ? (
                <div className="logs-empty">NO DETECTIONS LOGGED</div>
            ) : (
                <div className="logs-scroll">
                    <table className="data-table">
                        <thead className="table-sticky-head">
                            <tr>
                                {COLS.map((h) => (
                                    <th key={h}>{h}</th>
                                ))}
                            </tr>
                        </thead>
                        <tbody>
                            {[...logs].reverse().map((log, i) => (
                                <tr
                                    key={i}
                                    className={i % 2 === 0 ? "row-alt" : ""}
                                >
                                    <td>{log.datetime || log.timestamp}</td>
                                    <td>{Number(log.lat).toFixed(4)}</td>
                                    <td>{Number(log.lng).toFixed(4)}</td>
                                    <td>{log.area_m2}</td>
                                    <td>{log.depth_m}</td>
                                    <td>
                                        <span className="badge badge-accent">
                                            {log.volume_liters} L
                                        </span>
                                    </td>
                                    <td>
                                        <span
                                            className={confidenceBadgeClass(
                                                log.confidence,
                                            )}
                                        >
                                            {(
                                                Number(log.confidence) * 100
                                            ).toFixed(0)}
                                            %
                                        </span>
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            )}
        </div>
    );
}
