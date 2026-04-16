"""Production WSGI entry point for Gunicorn with eventlet."""
import os
from dotenv import load_dotenv

load_dotenv()

# Import Flask app with socketio already attached
from app import app

# Gunicorn will use 'app' as the WSGI application
# The socketio instance is already wrapped around app in app.py

if __name__ == "__main__":
    # Local debugging only (not used by Gunicorn)
    from app import socketio
    port = int(os.environ.get("PORT", 5000))
    socketio.run(app, host="0.0.0.0", port=port, debug=False)
