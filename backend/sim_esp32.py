"""
ESP32-CAM simulator -- sends images + random depth to /api/stream/frame.

"""

import argparse
import glob
import os
import random
import time

import requests

DEFAULT_SERVER = os.environ.get("SIM_SERVER", "http://localhost:5000/api")


def find_images(directory):
    exts = ("*.jpg", "*.jpeg", "*.png", "*.bmp")
    files = []
    for ext in exts:
        files.extend(glob.glob(os.path.join(directory, ext)))
        files.extend(glob.glob(os.path.join(directory, "**", ext), recursive=True))
    files = sorted(set(files))
    if not files:
        raise FileNotFoundError(f"No images found in {directory}")
    return files


def stream_loop(args):
    images = find_images(args.dir)
    url = f"{args.server}/stream/frame"
    delay = 1.0 / args.fps
    idx = 0

    print(f"[SIM] Streaming {len(images)} images to {url}")
    print(f"[SIM] FPS={args.fps}  depth={args.depth_min}-{args.depth_max}mm  loop={not args.no_loop}")

    session = requests.Session()

    try:
        while True:
            img_path = images[idx % len(images)]
            depth_mm = round(random.uniform(args.depth_min, args.depth_max), 1)
            lat = round(random.uniform(args.lat - 0.001, args.lat + 0.001), 6) if args.lat else 0.0
            lng = round(random.uniform(args.lng - 0.001, args.lng + 0.001), 6) if args.lng else 0.0

            with open(img_path, "rb") as f:
                files = {"image": (os.path.basename(img_path), f, "image/jpeg")}
                data = {"depth_mm": depth_mm, "lat": lat, "lng": lng}

                try:
                    t0 = time.time()
                    resp = session.post(url, files=files, data=data, timeout=15)
                    elapsed = (time.time() - t0) * 1000
                    status = resp.status_code
                except requests.RequestException as e:
                    elapsed = 0
                    status = f"ERR: {e}"

            print(f"  [{idx:04d}] {os.path.basename(img_path)}  depth={depth_mm}mm  -> {status}  ({elapsed:.0f}ms)")

            idx += 1
            if not args.no_loop and idx >= len(images):
                idx = 0
            elif args.no_loop and idx >= len(images):
                break

            time.sleep(delay)

    except KeyboardInterrupt:
        print(f"\n[SIM] Stopped after {idx} frames")


def single_detect(args):
    url = f"{args.server}/detect"
    depth_mm = round(random.uniform(args.depth_min, args.depth_max), 1)

    print(f"[SIM] Single detect: {args.single} -> {url}  depth={depth_mm}mm")

    with open(args.single, "rb") as f:
        files = {"image": (os.path.basename(args.single), f, "image/jpeg")}
        data = {"depth_mm": depth_mm, "lat": args.lat or 0, "lng": args.lng or 0}
        resp = requests.post(url, files=files, data=data, timeout=30)

    print(f"  Status: {resp.status_code}")
    try:
        import json
        body = resp.json()
        body.pop("annotated_image", None)
        print(json.dumps(body, indent=2))
    except Exception:
        print(resp.text[:500])


def main():
    parser = argparse.ArgumentParser(description="ESP32-CAM simulator")
    parser.add_argument("--server", default=DEFAULT_SERVER, help="API base URL")
    parser.add_argument("--dir", default="simulator_images", help="Image directory")
    parser.add_argument("--fps", type=float, default=15, help="Frames per second")
    parser.add_argument("--depth-min", type=float, default=15, help="Min random depth (mm)")
    parser.add_argument("--depth-max", type=float, default=120, help="Max random depth (mm)")
    parser.add_argument("--lat", type=float, default=0.0, help="Base latitude")
    parser.add_argument("--lng", type=float, default=0.0, help="Base longitude")
    parser.add_argument("--no-loop", action="store_true", help="Stop after one pass")
    parser.add_argument("--single", type=str, help="Single image -> /api/detect instead of stream")
    args = parser.parse_args()

    if args.single:
        single_detect(args)
    else:
        stream_loop(args)


if __name__ == "__main__":
    main()
