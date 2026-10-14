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

temp_txt=$(mktemp)
trap "rm -f $temp_txt" EXIT

# Resize to the character grid dimensions. The non-proportional resize is
# intentional: it compensates for the terminal character-cell aspect ratio.
magick "${image}[0]" -colorspace Gray -resize "${output_width}x${new_height}!" txt:"${temp_txt}"

current_y=-1
current_line=""

while IFS= read -r line; do
    # Skip comment lines and empty lines
    [[ "$line" =~ ^# ]] && continue
    [[ -z "$line" ]] && continue
    # Parse coordinates (format: "x,y:")
    coordinates="${line%%:*}"
    x=${coordinates%%,*}
    y=${coordinates##*,}
    # Extract grayscale value from "(r,g,b,a)" or "(g,alpha)" in IMv7
    grayscale=$(echo "$line" | sed 's/^[^(]*(//' | sed 's/[^0-9].*//')
    # Map grayscale (0-255) to charset index (0-8)
    index=$(( grayscale * charset_len / 255 ))
    [[ $index -gt $charset_len ]] && index=$charset_len
    char="${charset:$index:1}"
    # If we've moved to a new row, print the current line and start a new one

    if [[ $y -ne $current_y ]]; then
        [[ $current_y -ge 0 ]] && printf '%s\n' "$current_line"
        current_line=""
        current_y=$y
    fi

    current_line+="$char"
done < "$temp_txt"
# Print the last line
[[ -n "$current_line" ]] && printf '%s\n' "$current_line"
