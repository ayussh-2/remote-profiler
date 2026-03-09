from dotenv import load_dotenv
load_dotenv()

from flask import Flask
from flask_cors import CORS
from routes.detect import detect_bp
from routes.logs import logs_bp

app = Flask(__name__)
CORS(app)

app.register_blueprint(detect_bp, url_prefix="/api")
app.register_blueprint(logs_bp, url_prefix="/api")

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5000)
