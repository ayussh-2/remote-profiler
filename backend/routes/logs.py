from flask import Blueprint, jsonify
from utils.database import fetch_all_logs

logs_bp = Blueprint("logs", __name__)


@logs_bp.route("/logs", methods=["GET"])
def logs():
    try:
        data = fetch_all_logs()
        return jsonify({"status": "ok", "data": data}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
