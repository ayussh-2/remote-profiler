"""
Google Sheets integration via gspread.

Setup:
1. Create a Google Cloud project → enable Sheets API
2. Create a Service Account → download credentials JSON
3. Share your Google Sheet with the service account email
4. Set env vars:
   GOOGLE_CREDS_JSON = path to credentials JSON file
   GOOGLE_SHEET_ID   = your spreadsheet ID (from URL)

Sheet columns (auto-created on first run):
  timestamp | lat | lng | area_m2 | depth_m | volume_m3 | volume_liters | confidence
"""

import os
import json
import gspread
from google.oauth2.service_account import Credentials
from datetime import datetime

SCOPES = [
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/drive",
]

SHEET_HEADERS = [
    "timestamp", "datetime", "lat", "lng",
    "area_m2", "depth_m", "volume_m3", "volume_liters", "confidence",
    "severity", "estimated_cost_inr"
]

_client = None
_sheet = None


def _get_sheet():
    global _client, _sheet
    if _sheet is not None:
        return _sheet

    creds_path = os.environ.get("GOOGLE_CREDS_JSON", "credentials.json")
    sheet_id = os.environ.get("GOOGLE_SHEET_ID", "")

    if not sheet_id:
        raise EnvironmentError("GOOGLE_SHEET_ID env var not set")

    creds = Credentials.from_service_account_file(creds_path, scopes=SCOPES)
    _client = gspread.authorize(creds)
    spreadsheet = _client.open_by_key(sheet_id)

    try:
        _sheet = spreadsheet.sheet1
        # Ensure headers exist
        if _sheet.row_count == 0 or _sheet.row_values(1) != SHEET_HEADERS:
            _sheet.insert_row(SHEET_HEADERS, index=1)
    except Exception:
        _sheet = spreadsheet.add_worksheet(title="Detections", rows=1000, cols=20)
        _sheet.insert_row(SHEET_HEADERS, index=1)

    return _sheet


def append_to_sheet(payload: dict):
    """Append a detection result as a new row."""
    sheet = _get_sheet()
    dt = datetime.fromtimestamp(payload["timestamp"]).strftime("%Y-%m-%d %H:%M:%S")
    row = [
        payload["timestamp"],
        dt,
        payload.get("lat", 0),
        payload.get("lng", 0),
        payload.get("area_m2", 0),
        payload.get("depth_m", 0),
        payload.get("volume_m3", 0),
        payload.get("volume_liters", 0),
        payload.get("confidence", 0),
        payload.get("severity", ""),
        payload.get("estimated_cost_inr", 0),
    ]
    sheet.append_row(row, value_input_option="USER_ENTERED")


def fetch_all_logs() -> list[dict]:
    """Fetch all rows from the sheet as list of dicts."""
    sheet = _get_sheet()
    records = sheet.get_all_records()
    return records
