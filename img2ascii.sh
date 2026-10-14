#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    printf 'Usage: %s <image> [width]\n' "$0" >&2
    exit 1
fi

image=$1
width=${2:-80}
aspect_factor=1
charset="@%#*+=-:. "
charset_len=$(( ${#charset} - 1 ))

[[ -f "$image" ]] || {
    printf 'Error: file not found: %s\n' "$image" >&2
    exit 1
}

command -v magick >/dev/null 2>&1 || {
    printf 'Error: ImageMagick installation could not be verified (magick is required)\n' >&2
    exit 1
}

# Get original dimensions (use [0] to select first frame for multi-frame images)
img_frame="${image}[0]"
dimensions=$(magick identify -format '%w %h' "$img_frame")
read orig_width orig_height <<< "$dimensions"

# A character is taller than it is wide. The aspect factor additionally
# makes the output wider and shorter without changing the input image itself.
character_height_ratio=2
output_width=$(( width * aspect_factor ))
new_height=$(( (orig_height * width + orig_width * character_height_ratio * aspect_factor / 2) /
    (orig_width * character_height_ratio * aspect_factor) ))
new_height=$(( new_height > 0 ? new_height : 1 ))

magick "${image}[0]" -colorspace Gray \
    -resize "${output_width}x${new_height}!" txt:- |
    awk -v charset="$charset" -v charset_len="$charset_len" '
        /^#/ { next }
        {
            coordinate = $1
            sub(/:.*/, "", coordinate)
            split(coordinate, position, ",")
            y = position[2]

            match($0, /\([0-9][0-9]*/)
            grayscale = substr($0, RSTART + 1, RLENGTH - 1)
            char_index = int(grayscale * charset_len / 255)

            if (y != current_y) {
                if (current_y != "") {
                    print current_line
                }
                current_line = ""
                current_y = y
            }
            current_line = current_line substr(charset, char_index + 1, 1)
        }
        END {
            if (current_line != "") {
                print current_line
            }
        }
    '
