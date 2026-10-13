#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
        printf 'Usage: %s <image> [width]\n' "$0" >&2
        exit 1
fi

image=$1
width=${2:-80}

[[ -f "$image" ]] || {
        printf 'Error: file not found: %s\n' "$image" >&2
        exit 1
}

venv="${IMG2ASCII_VENV:-$HOME/.venvs/img2ascii}"
python="$venv/bin/python"

[[ -x "$python" ]] || {
        printf 'Error: Python venv not found: %s\n' "$venv" >&2
        printf 'Create it with:\n' >&2
        printf '  python3 -m venv %s\n' "$venv" >&2
        exit 1
}

"$python" - "$image" "$width" <<'PY'
import sys

from PIL import Image

image_path = sys.argv[1]
width = int(sys.argv[2])

charset = "@%#*+=-:. "

image = Image.open(image_path).convert("L")

height = max(
        1,
        round(image.height / image.width * width * 0.5)
)

image = image.resize((width, height))

pixels = image.load()

for y in range(image.height):
        for x in range(image.width):
                value = pixels[x, y]
                index = value * (len(charset) - 1) // 255
                print(charset[index], end="")
        print()
PY

