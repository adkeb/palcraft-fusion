#!/bin/sh
set -eu
PALCRAFT_SETUP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec python3 "$PALCRAFT_SETUP_DIR/launcher/install_player.py" --interactive "$@"
