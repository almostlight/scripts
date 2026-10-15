#!/usr/bin/env bash

set -Eeuo pipefail

# Usage:
#   ./download_public.sh URL [URL ...]
#   ./download_public.sh -f urls.txt
#   ./download_public.sh -o downloads URL [URL ...]

OUTDIR="."
URLS=()

while getopts ":o:f:" opt; do
    case "$opt" in
        o) OUTDIR="$OPTARG" ;;
        f)
            while IFS= read -r line || [[ -n "$line" ]]; do
                [[ -z "$line" || "$line" == \#* ]] && continue
                URLS+=("$line")
            done < "$OPTARG"
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 2
            ;;
    esac
done
shift $((OPTIND - 1))

URLS+=("$@")

if ((${#URLS[@]} == 0)); then
    echo "Usage: $0 [-o output_dir] [-f urls.txt] URL [URL ...]" >&2
    exit 2
fi

mkdir -p "$OUTDIR"

for url in "${URLS[@]}"; do
    echo "Downloading: $url"
    echo "Saving to:   $OUTDIR"

	if curl -fsSL --retry 3 \
	  -w '\n' \
	  -OJ \
      --output-dir "$OUTDIR" \
	  "${url%/}/download"; then
		echo "OK: $OUTDIR"
	else
		echo "FAILED: $url" >&2
	fi

    echo
done

