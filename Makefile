VPY = venv\Scripts\python.exe
VPIP = venv\Scripts\pip.exe
RELAYER_DIR = sensor-relayer

setup:
	cd backend && python -m venv venv && $(VPIP) install --upgrade pip && $(VPIP) install -r requirements.txt

install:
	cd backend && $(VPIP) install -r requirements.txt

dev-server:
	cd backend && $(VPY) app.py

dev-frontend:
	cd frontend\web && bun dev

dev-mobile:
	cd frontend\mobile && flutter run -v

dev-relayer:
	cd $(RELAYER_DIR) && go run .

build-relayer:
	cd $(RELAYER_DIR) && go build -o sensor-relayer.exe

docker-relayer:
	cd $(RELAYER_DIR) && docker build -t sensor-relayer:latest .

simulate:
	cd backend && $(VPY) sim_esp32.py --no-loop --fps 1

simulate-relayer:
	cd $(RELAYER_DIR) && python simulator.py

clean:
	cd backend && $(VPY) -c "import sqlite3; c=sqlite3.connect('detections.db'); c.execute('DELETE FROM detections'); c.commit(); print('flushed')"

build-apk:
	cd frontend\mobile && flutter build apk -v

.PHONY: setup install dev-server dev-frontend dev-mobile dev-relayer build-relayer docker-relayer simulate simulate-relayer clean build-apk
