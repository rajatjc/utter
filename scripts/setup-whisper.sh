#!/bin/bash
# Installs Utter's local Whisper speech recognition:
#   1. a private Python environment with mlx-whisper (~1.2 GB of packages)
#   2. the Whisper large-v3-turbo model (~1.6 GB, from Hugging Face)
# into ~/Library/Application Support/Utter. Nothing outside that folder (and the
# Hugging Face cache, ~/.cache/huggingface) is touched. Re-running is safe.
#
# Requirements: an Apple Silicon Mac and Python 3.10+ (Homebrew's python works:
# `brew install python`). To uninstall, delete the whisper-env folder below.
set -euo pipefail

ENV_DIR="$HOME/Library/Application Support/Utter/whisper-env"
MODEL="${UTTER_WHISPER_MODEL:-mlx-community/whisper-large-v3-turbo}"
MLX_WHISPER_VERSION="0.4.3"

if [ "$(uname -m)" != "arm64" ]; then
    echo "Whisper in Utter needs an Apple Silicon (M-series) Mac. Utter will use Apple's recognizer instead." >&2
    exit 1
fi

# Find Python 3.10 or newer (the macOS system Python is 3.9, too old).
PYTHON=""
for candidate in "${UTTER_PYTHON:-}" /opt/homebrew/bin/python3 python3.13 python3.12 python3.11 python3.10 python3; do
    [ -z "$candidate" ] && continue
    if command -v "$candidate" >/dev/null 2>&1 &&
       "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
        PYTHON="$(command -v "$candidate")"
        break
    fi
done
if [ -z "$PYTHON" ]; then
    echo "Python 3.10 or newer is required. Install it with:  brew install python" >&2
    echo "(No Homebrew? See https://brew.sh, or install Python from https://www.python.org/downloads/macos/)" >&2
    exit 1
fi
echo "Using $PYTHON ($("$PYTHON" --version))"

if [ ! -x "$ENV_DIR/bin/python" ]; then
    echo "Creating the Whisper environment in: $ENV_DIR"
    mkdir -p "$(dirname "$ENV_DIR")"
    "$PYTHON" -m venv "$ENV_DIR"
fi

echo "Installing mlx-whisper $MLX_WHISPER_VERSION (about 1.2 GB the first time)..."
"$ENV_DIR/bin/python" -m pip install --quiet --upgrade pip
"$ENV_DIR/bin/python" -m pip install --quiet "mlx-whisper==$MLX_WHISPER_VERSION"

echo "Downloading the model $MODEL (about 1.6 GB the first time)..."
"$ENV_DIR/bin/python" - "$MODEL" <<'EOF'
import sys
from huggingface_hub import snapshot_download
path = snapshot_download(sys.argv[1])
print("Model ready at", path)
EOF

echo "Checking that it loads..."
"$ENV_DIR/bin/python" -c "import mlx_whisper, numpy; print('mlx-whisper OK')"

echo
echo "Done. Restart Utter (or click Restart in Settings → AI & dictation) to use Whisper."
