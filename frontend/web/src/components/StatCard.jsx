export default function StatCard({ label, value, unit, size = "md" }) {
    return (
        <div className="stat-box">
            <span className="label">{label}</span>
            <div className={`stat-val stat-val--${size}`}>
                {value}
                {unit && <span className="stat-unit">{unit}</span>}
            </div>
        </div>
    );
}
