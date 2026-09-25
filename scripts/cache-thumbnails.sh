#!/bin/bash
# Downloads each catalog entry's thumbnail into cache/thumbs/<slug>.<ext> so
# the panel can reference local files instead of loading images over the
# network on every open.

set -euo pipefail

# Not under the plugin dir: Omarchy watches every plugin's own directory
# recursively to hot-reload on code changes, so writing hundreds of
# thumbnails there gets misread as a code change and force-closes this
# panel mid-refresh. XDG_CACHE_HOME is outside that watch.
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-theme-gallery"
CATALOG="$CACHE_DIR/catalog.json"
THUMBS_DIR="$CACHE_DIR/thumbs"
UA="omarchy-theme-gallery/0.1 (local Omarchy plugin; caches theme thumbnails)"
# Card thumbnails are small preview images; this is a generous cap against a
# broken or hostile response filling the disk during Refresh.
MAX_IMAGE_BYTES=10000000

[[ -f $CATALOG ]] || { echo "catalog.json not found — run scrape-catalog.sh first" >&2; exit 1; }

mkdir -p "$THUMBS_DIR"

total=$(jq '.themes | length' "$CATALOG")
count=0

jq -r '.themes[] | select(.thumb) | "\(.slug)\t\(.thumb)"' "$CATALOG" | while IFS=$'\t' read -r slug url; do
  count=$((count + 1))
  ext="${url##*.}"
  ext="${ext%%[?#]*}"
  [[ $ext =~ ^(jpg|jpeg|png|webp|gif)$ ]] || ext="jpg"
  dest="$THUMBS_DIR/$slug.$ext"

  if [[ -s $dest ]]; then
    echo "[$count/$total] $slug (cached)" >&2
    continue
  fi

  echo "[$count/$total] $slug" >&2
  curl -s -A "$UA" --max-time 15 --retry 2 --max-filesize "$MAX_IMAGE_BYTES" -o "$dest.part" "$url" && mv "$dest.part" "$dest" || {
    echo "  -> failed to fetch $url" >&2
    rm -f "$dest.part"
  }
done

echo "Cached $(find "$THUMBS_DIR" -type f | wc -l) thumbnails in $THUMBS_DIR" >&2
