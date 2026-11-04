#!/usr/bin/env python3
"""4x6 label PDF -> raw ZPL for the 300 dpi ZD420 (1200x1800). Rotated 180 degrees (York 2026-11-04:
"flip it 180 degrees when u print them" - the station-3 Zebra feeds so an unrotated label comes out upside down).
Usage: tools-pdf2zpl.py label.pdf out.zpl [--no-rotate]
"""
import sys, subprocess, tempfile, os
from PIL import Image
pdf, out = sys.argv[1], sys.argv[2]
rotate = "--no-rotate" not in sys.argv
tmp = tempfile.mkdtemp()
subprocess.run(["pdftoppm", "-r", "300", "-png", "-mono", "-singlefile", pdf, os.path.join(tmp, "p")], check=True)
im = Image.open(os.path.join(tmp, "p.png")).convert("1")
W, H = 1200, 1800
canvas = Image.new("1", (W, H), 1); canvas.paste(im, (0, 0))
if rotate: canvas = canvas.rotate(180)
inv = bytes(b ^ 0xFF for b in canvas.tobytes())  # PIL 1=white, ZPL ^GFA 1=black
zpl = f"^XA^PW{W}^LL{H}^LH0,0^FO0,0^GFA,{len(inv)},{len(inv)},150,{inv.hex().upper()}^FS^PQ1^XZ"
open(out, "w").write(zpl); print(out, len(zpl), "bytes", "rotated" if rotate else "unrotated")
