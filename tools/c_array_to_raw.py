#!/usr/bin/env python3
"""c_array_to_raw.py — dump the first C array literal in a header as raw bytes.

Used to produce examples/zig/others/resources/*.raw from raylib's
examples/others/resources/{image,audio}_data.h (ExportImageAsCode /
ExportWaveAsCode output): the element type is read from the declaration
(unsigned char -> 1 byte, short -> 2, float -> 4, little-endian), so the raw
file holds exactly the array's in-memory bytes.

Usage: python3 tools/c_array_to_raw.py <header.h> <out.raw>
"""
import re
import struct
import sys

src = open(sys.argv[1]).read()
decl = re.search(r"(unsigned char|short|float)\s+\w+\[[^\]]*\]\s*=\s*\{(.*?)\};", src, re.S)
ctype, body = decl.group(1), decl.group(2)
values = [v for v in re.split(r"[,\s]+", body) if v]
fmt = {"unsigned char": "B", "short": "h", "float": "f"}[ctype]
conv = (lambda v: float(v.rstrip("f"))) if ctype == "float" else (lambda v: int(v, 0))
with open(sys.argv[2], "wb") as out:
    out.write(struct.pack("<" + fmt * len(values), *[conv(v) for v in values]))
