import urllib.request
import time
import json
import random
import os
import glob

RELAY_URL = "https://remote-profiler-2-production.up.railway.app"
# RELAY_URL = "http://localhost:5001"
IMAGE_DIR = r"d:\Projects\Personal\profiler\backend\simulator_images"
image_files = glob.glob(os.path.join(IMAGE_DIR, "*.jpg"))

if not image_files:
    print(f"Warning: No images found in {IMAGE_DIR}")

def send_frame():
    if not image_files:
        return False
        
    img_path = random.choice(image_files)
    with open(img_path, "rb") as f:
        img_bytes = f.read()
        
    req = urllib.request.Request(f"{RELAY_URL}/api/frame", data=img_bytes)
    print(f"{RELAY_URL}/api/frame")
    req.add_header("Content-Type", "image/jpeg")
    try:
        with urllib.request.urlopen(req) as res:
            return True
    except Exception as e:
        print(f"\n[Error] /api/frame failed: {e}")
        return False

def send_depth():
    depth_val = random.uniform(100.0, 2000.0)
    data = json.dumps({"distance": depth_val}).encode("utf-8")
    req = urllib.request.Request(f"{RELAY_URL}/api/depth", data=data)
    print(f"{RELAY_URL}/api/depth")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as res:
            return True
    except Exception as e:
        print(f"\n[Error] /api/depth failed: {e}")
        return False

def send_gps():
    lat = random.uniform(28.0, 29.0)
    lng = random.uniform(77.0, 78.0)
    data = json.dumps({"lat": lat, "lng": lng}).encode("utf-8")
    req = urllib.request.Request(f"{RELAY_URL}/api/gps", data=data)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as res:
            return True
    except Exception as e:
        print(f"\n[Error] /api/gps failed: {e}")
        return False

def main():
    print(f"🚀 Starting simulator. Sending data to {RELAY_URL}")
    print("Press Ctrl+C to stop.\n")
    
    count = 0
    try:
        while True:
            # Randomly jitter the order to test alignment timing,
            # or send them back to back
            if random.random() > 0.5:
                send_frame()
                send_depth()
            else:
                send_depth()
                send_frame()
            
            # Optionally send GPS occasionally
            if count % 5 == 0:
                send_gps()
            
            count += 1
            print(".", end="", flush=True)
            time.sleep(1) # Send at 1 FPS simulate rate
    except KeyboardInterrupt:
        print("\n⏹ Simulator stopped.")

if __name__ == "__main__":
    main()
