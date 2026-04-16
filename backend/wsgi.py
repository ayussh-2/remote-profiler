"""Production WSGI entry point for Gunicorn with eventlet."""
# eventlet monkey-patch MUST be first — before any other imports
import eventlet
eventlet.monkey_patch()

import os
from dotenv import load_dotenv
load_dotenv()
from app import app  # noqa: E402

if __name__ == "__main__":
    from app import socketio
    port = int(os.environ.get("PORT", 5000))
    socketio.run(app, host="0.0.0.0", port=port, debug=False)
