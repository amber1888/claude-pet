#!/usr/bin/env python3
"""把 video-look.sh 量出的每张精灵图帧数（frames.json）写进形象的 character.json：
不满 120 帧的动画加 "to"（最后一帧的序号），不然会播到后面的空白格。
用法：look-frames.py <character.json> <frames.json> <输出的 character.json>"""
import json
import sys

ch = json.load(open(sys.argv[1]))
frames = json.load(open(sys.argv[2]))
for pose, a in ch.get("animations", {}).items():
    sheets = a.get("sheets", [])
    missing = [s for s in sheets if s not in frames]
    if missing:
        sys.exit(f"{pose} 用了没生成的精灵图：{missing}")
    ns = [frames[s] for s in sheets]
    if ns and min(ns) < 120:
        a["to"] = min(ns) - 1
json.dump(ch, open(sys.argv[3], "w"), ensure_ascii=False, indent=2)
