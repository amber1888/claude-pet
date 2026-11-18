#!/bin/bash
# 把一组带透明通道的 WebM 动画（VP9 + alpha，比如克劳德大小姐 Claude-girl 的 clips/）转成桌宠能用的形象：
#   anim/<名字>.webp   精灵图：8 列 × 15 行，每格 640×360，12 帧/秒，最多 120 帧（网页 index.html 的 SHEET）
#   <姿态>.webp        静态立绘：640 高，站着的人物 638 高，脚踩底边、左右居中（动画关掉、省电模式时用）
# macOS 的 WebKit 播 VP9 时会丢掉透明通道（人物外面一个黑框），所以不能直接播 webm，要先转。
# 所有片段是同一个机位拍的：按校准片段（一般是待机）里人物的高度、脚的位置、左右中心算一次缩放和平移，所有片段都照这个摆，
# 这样换动作时人物不会忽大忽小、跳来跳去。
#
# 用法：scripts/video-look.sh <片段目录> <输出目录> <说明文件>
# 说明文件每行一条（# 开头是注释）：
#   calibrate <片段>                     用哪个片段校准（人物站直、不拿道具的那个）
#   sheet <名字> <片段>[+<片段>…]        一张精灵图；几个片段接起来（比如拿出茶杯 + 喝茶 + 收起茶杯），超过 10 秒就整体加速塞进 120 帧
#   still <姿态> <片段> <位置 0~1>        一张静态立绘，取片段里这个位置的那一帧
# 输出目录里另外写 frames.json：每张精灵图实际有几帧（{"名字": 帧数}），character.json 里的 "to" 照它填
# 需要：ffmpeg（要带 libvpx，才解得出透明通道）、cwebp。brew install ffmpeg webp
set -euo pipefail
CLIPS="$1"; OUT="$2"; SPEC="$3"
for t in ffmpeg ffprobe cwebp; do command -v "$t" >/dev/null || { echo "缺少 ${t}：brew install ffmpeg webp" >&2; exit 2; }; done
decoders="$(ffmpeg -hide_banner -decoders 2>/dev/null)"
[[ "$decoders" == *libvpx-vp9* ]] || { echo "ffmpeg 没带 libvpx-vp9，解不出透明通道" >&2; exit 2; }

# 和 web/index.html 的 SHEET 一致
FW=640; FH=360; COLS=8; ROWS=15; FPS=12; MAXF=120; CHAR_H=281; FEET_Y=321; CENTER_X=325
STILL_W=600; STILL_H=640; STILL_CHAR=638

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT/anim"
dec() { echo -c:v libvpx-vp9 -i "$CLIPS/$1.webm"; }   # 一定要用 libvpx 解码，ffmpeg 自带的 vp9 解码器会丢 alpha
dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$CLIPS/$1.webm"; }

# ---- 校准：校准片段所有帧不透明部分合起来的外框（alpha-bbox.py 量；ffmpeg 的 cropdetect 量 alpha 不准）----
cal="$(awk '$1=="calibrate"{print $2}' "$SPEC")"
read -r VW VH < <(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$CLIPS/$cal.webm" | tr ',' ' ')
read -r BW BH BX BY < <(ffmpeg -nostdin -hide_banner -loglevel error $(dec "$cal") -vf "fps=4,alphaextract" -pix_fmt gray -f rawvideo - \
  | python3 -I "$(dirname "$0")/alpha-bbox.py" "$VW" "$VH")
echo "校准 ${cal}：人物 ${BW}×${BH}，左上 (${BX},${BY})，视频 ${VW}×${VH}"
# 精灵图：人物高 → CHAR_H，脚 → FEET_Y，中心 → CENTER_X；静态图：人物高 → STILL_CHAR，脚踩底边（留 1 像素），中心 → 宽的一半
read -r SW SH SX SY TW TH TX TY < <(python3 -c "
bw,bh,bx,by,vw,vh=$BW,$BH,$BX,$BY,$VW,$VH
feet,cx=by+bh,bx+bw/2
s=$CHAR_H/bh; t=$STILL_CHAR/bh
print(round(vw*s),round(vh*s),round($CENTER_X-cx*s),round($FEET_Y-feet*s),
      round(vw*t),round(vh*t),round($STILL_W/2-cx*t),round($STILL_H-1-feet*t))")

frames_json="{"
while read -r kind a b c; do
  case "$kind" in
  sheet)
    name="$a"; IFS='+' read -r -a parts <<< "$b"
    inputs=(); chain=""; total=0
    for i in "${!parts[@]}"; do
      inputs+=($(dec "${parts[$i]}")); chain+="[$i:v]"
      total="$(python3 -c "print($total+$(dur "${parts[$i]}"))")"
    done
    # 帧数：超过 10 秒就整体加速（setpts）塞进 120 帧
    read -r speed n < <(python3 -c "
t=$total; n=int(t*$FPS)
print(f'{min(1.0,$MAXF/n):.6f}', min(n,$MAXF))")
    join="${chain}concat=n=${#parts[@]}:v=1:a=0,setpts=PTS*${speed}"
    ffmpeg -nostdin -y -hide_banner -loglevel error "${inputs[@]}" -f lavfi -i "color=c=black@0.0:s=${FW}x${FH}:r=${FPS},format=rgba" -filter_complex \
      "${join},fps=${FPS},scale=${SW}:${SH}:flags=lanczos,format=rgba[fg];[${#parts[@]}:v][fg]overlay=x=${SX}:y=${SY}:shortest=1:format=auto,format=rgba,trim=end_frame=${MAXF},tile=${COLS}x${ROWS}:color=black@0.0" \
      -frames:v 1 -pix_fmt rgba "$TMP/sheet.png"
    cwebp -quiet -q 82 -alpha_q 90 -m 5 "$TMP/sheet.png" -o "$OUT/anim/$name.webp"
    frames_json+="\"$name\": $n, "
    echo "精灵图 ${name}（${b}，${n} 帧$( [ "$speed" != "1.000000" ] && echo "，加速 $(python3 -c "print(round(1/$speed,2))") 倍" )）"
    ;;
  still)
    pose="$a"; clip="$b"; at="$(python3 -c "print(max(0.0, min($(dur "$b")-0.05, $(dur "$b")*$c)))")"
    ffmpeg -nostdin -y -hide_banner -loglevel error -c:v libvpx-vp9 -ss "$at" -i "$CLIPS/$clip.webm" -f lavfi -i "color=c=black@0.0:s=${STILL_W}x${STILL_H},format=rgba" \
      -filter_complex "[0:v]scale=${TW}:${TH}:flags=lanczos,format=rgba[fg];[1:v][fg]overlay=x=${TX}:y=${TY}:format=auto,format=rgba" \
      -frames:v 1 -pix_fmt rgba "$TMP/still.png"
    cwebp -quiet -q 90 -alpha_q 95 -m 5 "$TMP/still.png" -o "$OUT/$pose.webp"
    ;;
  esac
done < <(grep -v '^[[:space:]]*\(#\|$\)' "$SPEC")
echo "${frames_json%, }}" > "$OUT/frames.json"
echo "完成：${OUT}（$(du -sh "$OUT" | cut -f1)）"
