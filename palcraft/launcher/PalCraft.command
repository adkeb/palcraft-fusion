#!/bin/sh
set -eu
PALCRAFT_TOOLS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if ! command -v python3 >/dev/null 2>&1; then
  printf '%s\n' '找不到 Python 3。请先安装发布指南要求的 Python，再重新打开。'
  read -r PALCRAFT_CLOSE
  exit 2
fi
python3 "$PALCRAFT_TOOLS_DIR/launcher/palcraft.py" menu "$@"
