import { useState } from "react";
import { FlaskConical, CheckCircle, XCircle, Loader } from "lucide-react";

const STATUS_ICON = {
    idle: null,
    loading: <Loader size={13} className="spin" />,
    ok: <CheckCircle size={13} color="var(--green)" />,
    error: <XCircle size={13} color="var(--red)" />,
};

export default function SheetsTest({ apiBase }) {
    const [status, setStatus] = useState("idle"); // idle | loading | ok | error
    const [result, setResult] = useState(null);
    const [open, setOpen] = useState(false);

    const run = async () => {
        setStatus("loading");
        setResult(null);
        setOpen(true);
        try {
            const res = await fetch(`${apiBase}/test/sheets`, {
                method: "POST",
            });
            const data = await res.json();
            setStatus(data.status === "ok" ? "ok" : "error");
            setResult(data);
        } catch (e) {
            setStatus("error");
            setResult({ error: e.message });
        }
    };

    return (
        <>
            {/* Trigger button */}
            <button
                onClick={run}
                disabled={status === "loading"}
                title="Test Google Sheets connection"
                style={{
                    background: "none",
                    border: "1px solid var(--border)",
                    borderRadius: 5,
                    color: "var(--muted)",
                    cursor: status === "loading" ? "not-allowed" : "pointer",
                    display: "flex",
                    alignItems: "center",
                    gap: 5,
                    fontFamily: "inherit",
                    fontSize: 9,
                    letterSpacing: 2,
                    padding: "4px 10px",
                    textTransform: "uppercase",
                    transition: "border-color 0.15s, color 0.15s",
                }}
            >
                <FlaskConical size={11} />
                Test Sheets
                {STATUS_ICON[status]}
            </button>

            {/* Result panel */}
            {open && (
                <div
                    style={{
                        position: "fixed",
                        inset: 0,
                        background: "#00000088",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        zIndex: 9999,
                    }}
                    onClick={(e) =>
                        e.target === e.currentTarget && setOpen(false)
                    }
                >
                    <div
                        style={{
                            background: "var(--panel)",
                            border: "1px solid var(--border)",
                            borderRadius: 8,
                            padding: 24,
                            width: 480,
                            maxWidth: "90vw",
                            fontFamily: "inherit",
                        }}
                    >
                        {/* modal header */}
                        <div
                            style={{
                                display: "flex",
                                alignItems: "center",
                                gap: 8,
                                marginBottom: 16,
                            }}
                        >
                            <span className="label" style={{ marginBottom: 0 }}>
                                Google Sheets Diagnostics
                            </span>
                            {STATUS_ICON[status]}
                            <button
                                onClick={() => setOpen(false)}
                                style={{
                                    marginLeft: "auto",
                                    background: "none",
                                    border: "none",
                                    color: "var(--muted)",
                                    cursor: "pointer",
                                    fontSize: 16,
                                    lineHeight: 1,
                                }}
                            >
                                ×
                            </button>
                        </div>

                        {status === "loading" && (
                            <div
                                style={{
                                    color: "var(--muted)",
                                    fontSize: 11,
                                    letterSpacing: 1,
                                }}
                            >
                                Writing dummy row and reading back…
                            </div>
                        )}

                        {status === "ok" && result && (
                            <div
                                style={{
                                    display: "flex",
                                    flexDirection: "column",
                                    gap: 12,
                                }}
                            >
                                <Row
                                    label="Status"
                                    value={
                                        <span className="badge badge-green">
                                            Connected
                                        </span>
                                    }
                                />
                                <Row
                                    label="Total rows in sheet"
                                    value={result.row_count}
                                />
                                <div>
                                    <span className="label">Written row</span>
                                    <Pre data={result.written_row} />
                                </div>
                                <div>
                                    <span className="label">
                                        Last {result.last_rows?.length} rows
                                        read back
                                    </span>
                                    <Pre data={result.last_rows} />
                                </div>
                            </div>
                        )}

                        {status === "error" && result && (
                            <div
                                style={{
                                    display: "flex",
                                    flexDirection: "column",
                                    gap: 10,
                                }}
                            >
                                <Row
                                    label="Status"
                                    value={
                                        <span className="badge badge-red">
                                            Failed
                                        </span>
                                    }
                                />
                                {result.stage && (
                                    <Row
                                        label="Failed at"
                                        value={result.stage}
                                    />
                                )}
                                <div className="error-banner">
                                    {result.error}
                                </div>
                                <div
                                    style={{
                                        fontSize: 10,
                                        color: "var(--muted)",
                                        lineHeight: 1.6,
                                    }}
                                >
                                    Common causes:
                                    <br />• <b>GOOGLE_SHEET_ID</b> not set in{" "}
                                    <code>.env</code>
                                    <br />• <b>credentials.json</b> missing or
                                    wrong path
                                    <br />• Sheet not shared with the service
                                    account email
                                </div>
                            </div>
                        )}
                    </div>
                </div>
            )}
        </>
    );
}

function Row({ label, value }) {
    return (
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <span
                style={{ fontSize: 10, color: "var(--muted)", minWidth: 140 }}
            >
                {label}
            </span>
            <span style={{ fontSize: 11, color: "var(--text)" }}>{value}</span>
        </div>
    );
}

function Pre({ data }) {
    return (
        <pre
            style={{
                margin: "6px 0 0",
                background: "var(--bg)",
                border: "1px solid var(--border)",
                borderRadius: 4,
                padding: "8px 10px",
                fontSize: 10,
                color: "var(--text)",
                overflowX: "auto",
                lineHeight: 1.6,
            }}
        >
            {JSON.stringify(data, null, 2)}
        </pre>
    );
}
