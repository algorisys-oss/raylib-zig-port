#!/usr/bin/env python3
"""Convert the scene_runner's raw RGBA framebuffer dumps to viewable PNGs.

The scene runner writes <dir>/NN_name.raw as width*height*4 bytes of RGBA. The
gate compares those bytes directly; this is just so a human can eyeball them.

Usage: python3 tools/frames_to_png.py [frames_dir]   (default: zig-out/frames)
Writes a .png next to each .raw. Scenes are 640x360 (see test/scene_runner.c).
"""
import glob
import os
import sys

from PIL import Image

W, H = 640, 360
d = sys.argv[1] if len(sys.argv) > 1 else "zig-out/frames"
raws = sorted(glob.glob(os.path.join(d, "*.raw")))
if not raws:
    sys.exit(f"no .raw files in {d} — run `zig build demo` first (after mkdir -p {d})")
for r in raws:
    data = open(r, "rb").read()
    if len(data) != W * H * 4:
        print(f"  skip {os.path.basename(r)}: {len(data)} bytes != {W*H*4}")
        continue
    out = r[:-4] + ".png"
    Image.frombytes("RGBA", (W, H), data).save(out)
    print(f"  {os.path.basename(out)}")
print(f"done -> {d}/*.png")
