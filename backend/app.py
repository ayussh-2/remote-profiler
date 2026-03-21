from dotenv import load_dotenv
load_dotenv()

from flask import Flask
from flask_cors import CORS
from flask_socketio import SocketIO
from routes.detect import detect_bp
from routes.logs import logs_bp

from routes.stream import stream_bp, init_stream_events
from utils.material_estimator import enable_ml_mode
from utils.database import init_db

app = Flask(__name__)
CORS(app)

socketio = SocketIO(app, cors_allowed_origins="*", async_mode="eventlet")
init_stream_events(socketio)

init_db()

ml_status = enable_ml_mode('models/material_estimator')
if not ml_status:
    print("[APP] ML models not available -- using rule-based estimation")


@app.get("/")
def index():
    return {"message": "Hello, World!"}


app.register_blueprint(detect_bp, url_prefix="/api")
app.register_blueprint(logs_bp, url_prefix="/api")

app.register_blueprint(stream_bp, url_prefix="/api")

if __name__ == "__main__":
    socketio.run(app, debug=True, host="0.0.0.0", port=5000)
