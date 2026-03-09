# Pavement Profiler — Frontend

React dashboard for pothole detection results, GPS map, and detection log.

## Stack

- React 18
- Vite 6
- Leaflet (via CDN) for map
- No CSS framework — inline styles only

## Structure

```
frontend/
├── index.html
├── vite.config.js
├── package.json
└── src/
    ├── main.jsx            # React root
    └── App.jsx             # full dashboard (map + controls + log table)
```

## Setup

```bash
cd frontend
npm install
```

## Run

```bash
npm run dev
# Dashboard at http://localhost:5173
```

Vite proxies all `/api` requests to `http://localhost:5000` — the backend must be running.

## Build (production)

```bash
npm run build
# Output in frontend/dist/
```

## Features

| Panel        | Description                                                                          |
| ------------ | ------------------------------------------------------------------------------------ |
| Left sidebar | Image upload, ToF depth input, GPS coords, run detection button, latest result stats |
| Top right    | Leaflet map with pothole pins (orange dot per detection)                             |
| Bottom right | Detection log table pulled from Google Sheets via `/api/logs`                        |

## Configuration

`API_BASE` is set at the top of [src/App.jsx](src/App.jsx):

```js
const API_BASE = "http://localhost:5000/api";
```

In dev mode the Vite proxy handles this automatically. For production, update `API_BASE` to your deployed backend URL.
