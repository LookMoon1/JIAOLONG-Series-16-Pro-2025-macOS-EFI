#!/usr/bin/env bash
# OpenCore config.plist 校验（包装 validate.py，兼容 macOS / Linux）
#
# 用法:
#   ./scripts/validate.sh /Volumes/EFI/EFI/OC/config.plist

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PY_SCRIPT="$HERE/validate.py"

if [ $# -ne 1 ]; then
    echo "用法: $0 <path/to/config.plist>" >&2
    exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "错误: 需要 python3" >&2
    exit 2
fi

exec python3 "$PY_SCRIPT" "$1"
