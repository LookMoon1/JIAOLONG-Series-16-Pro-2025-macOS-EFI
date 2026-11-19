#!/bin/bash
# 记录 EC 快照变化，用于定位档位/风扇/温度寄存器
# 用法: ./watch.sh <输出文件> <秒数>
OUT="${1:-ecwatch.log}"
SECS="${2:-120}"
HERE="$(cd "$(dirname "$0")" && pwd)"
END=$(( $(date +%s) + SECS ))
: > "$OUT"
last=""
while [ "$(date +%s)" -lt "$END" ]; do
  line=$("$HERE/ecdump" -r 2>/dev/null)
  if [ -n "$line" ] && [ "$line" != "$last" ]; then
    echo "$(date +%H:%M:%S) $line" >> "$OUT"
    last="$line"
  fi
  sleep 1
done
echo "done lines=$(wc -l < "$OUT")"
