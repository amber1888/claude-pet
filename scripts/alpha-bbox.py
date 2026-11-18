#!/usr/bin/env python3
"""从 stdin 读 ffmpeg 输出的原始灰度帧（-pix_fmt gray -f rawvideo，每帧 宽×高 字节，这里是 alpha），
输出所有帧里不透明部分合起来的外框：宽 高 左 上。只用标准库。
用法：ffmpeg … -vf alphaextract -pix_fmt gray -f rawvideo - | alpha-bbox.py <宽> <高> [阈值]"""
import sys
w, h = int(sys.argv[1]), int(sys.argv[2])
th = int(sys.argv[3]) if len(sys.argv) > 3 else 24
top, bottom, left, right = h, -1, w, -1
size = w * h
src = sys.stdin.buffer
while True:
    f = src.read(size)
    if len(f) < size:
        break
    rows = [y for y in range(h) if max(f[y * w:(y + 1) * w]) > th]
    if not rows:
        continue
    top, bottom = min(top, rows[0]), max(bottom, rows[-1])
    band = f[rows[0] * w:(rows[-1] + 1) * w]
    cols = [x for x in range(w) if max(band[x::w]) > th]
    left, right = min(left, cols[0]), max(right, cols[-1])
if bottom < 0:
    sys.exit("全透明")
print(right - left + 1, bottom - top + 1, left, top)
