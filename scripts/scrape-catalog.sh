#!/bin/bash
# Scrapes https://omarchythemes.com/ into a local catalog.json of
# {slug, name, author, repo, thumb, apps[]} so the theme-gallery plugin can
# browse/install themes without hitting the site on every open.
#
# Usage:
#   scrape-catalog.sh [--limit N] [--delay SECONDS] [--out FILE] [--slug SLUG]

set -euo pipefail

BASE="https://omarchythemes.com"
UA="omarchy-theme-gallery/0.1 (local Omarchy plugin; scrapes theme list for one-click install)"
# Listing/detail pages are a few hundred KB at most; this is a generous cap
# against a broken or hostile response ballooning a bash variable in memory.
MAX_PAGE_BYTES=2000000
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
OUT_FILE="$PLUGIN_DIR/cache/catalog.json"
DELAY="0.4"
LIMIT=""
ONLY_SLUG=""

while (( $# > 0 )); do
  case "$1" in
  --limit) LIMIT="$2"; shift 2 ;;
  --delay) DELAY="$2"; shift 2 ;;
  --out) OUT_FILE="$2"; shift 2 ;;
  --slug) ONLY_SLUG="$2"; shift 2 ;;
  -h | --help)
    echo "Usage: $0 [--limit N] [--delay SECONDS] [--out FILE] [--slug SLUG]"
    exit 0
    ;;
  *)
    echo "unknown option: $1" >&2
    exit 1
    ;;
  esac
done

fetch() {
  curl -s -A "$UA" --max-time 15 --retry 2 --retry-delay 1 --max-filesize "$MAX_PAGE_BYTES" "$1"
}

# Extracts one field via a sed pattern; prints empty string (not an error) on no match.
extract() {
  sed -nE "$1" | head -n1
}

parse_theme_page() {
  local slug="$1" html="$2"
  local name author repo thumb apps_json kind

  name=$(printf '%s' "$html" | extract 's#.*<h1[^>]*>([^<]+)</h1>.*#\1#p')
  author=$(printf '%s' "$html" | extract 's#.*<p class="text-sm">By ([^<]+)</p>.*#\1#p')
  thumb=$(printf '%s' "$html" | grep -oE '<img class="rounded-lg"[^>]*src="[^"]+"' | grep -oE 'src="[^"]+"' | head -n1 | sed -E 's/^src="//; s/"$//')
  # The repo link is the "Learn more" button: an <a> whose href comes right
  # after the tag name and that opens in a new tab. Not always github.com —
  # some authors host on codeberg.org, gitlab.com, etc. — so match any host.
  # (The footer's own target="_blank" link puts target before href, so it
  # doesn't match this attribute order and is excluded by construction.)
  repo=$(printf '%s' "$html" | grep -oE '<a href="[^"]+"[^>]*target="_blank"' | head -n1 | sed -E 's#^<a href="([^"]*)".*#\1#')

  apps_json=$(printf '%s' "$html" | grep -oE '<p>[a-z0-9_-]+</p>' | sed -E 's#<p>##; s#</p>##' | jq -R -s -c 'split("\n") | map(select(length > 0))')

  # Omarchy's own stock themes (gruvbox, nord, tokyo-night, ...) carry an
  # "Official" badge instead of a GitHub link: they ship with Omarchy already
  # and are switched to with `omarchy theme set`, never `theme install`.
  if printf '%s' "$html" | grep -q '<span>Official</span>'; then
    kind="official"
  else
    kind="community"
  fi

  [[ -n $name ]] || { echo "  -> skip $slug: missing name" >&2; return 1; }
  [[ -n $repo || $kind == official ]] || { echo "  -> skip $slug: missing repo" >&2; return 1; }

  # A couple of "Official" themes (flexoki-light, solarized) still link to a
  # real installable repo instead of the manual, so gate on the link's host
  # rather than on the badge: only github/gitlab/codeberg/sourcehut/bitbucket
  # links are something `omarchy theme install` can actually clone. Anything
  # else (typically the Omarchy manual page for a bundled theme) is not.
  jq -n \
    --arg slug "$slug" \
    --arg name "$name" \
    --arg author "$author" \
    --arg repo "$repo" \
    --arg thumb "$thumb" \
    --arg kind "$kind" \
    --argjson apps "$apps_json" \
    '{
      slug: $slug, name: $name, author: $author, kind: $kind, thumb: $thumb, apps: $apps,
      repo: (if ($repo | test("^https://(github\\.com|gitlab\\.com|codeberg\\.org|git\\.sr\\.ht|bitbucket\\.org)/"))
             then $repo else null end)
    }'
}

mkdir -p "$(dirname "$OUT_FILE")"

if [[ -n $ONLY_SLUG ]]; then
  slugs=("$ONLY_SLUG")
else
  echo "Fetching theme list from $BASE ..." >&2
  listing=$(fetch "$BASE/")
  mapfile -t slugs < <(printf '%s' "$listing" | grep -oE "href=\"$BASE/themes/[a-zA-Z0-9_-]+\"" | sed -E "s#href=\"$BASE/themes/##; s#\"##" | sort -u)
  [[ ${#slugs[@]} -gt 0 ]] || { echo "No theme links found on listing page — site markup may have changed." >&2; exit 1; }
  echo "Found ${#slugs[@]} themes." >&2
  if [[ -n $LIMIT ]]; then
    slugs=("${slugs[@]:0:$LIMIT}")
  fi
fi

tmp_entries="$(mktemp)"
trap 'rm -f "$tmp_entries"' EXIT

count=0
total=${#slugs[@]}
for slug in "${slugs[@]}"; do
  count=$((count + 1))
  echo "[$count/$total] $slug" >&2
  page=$(fetch "$BASE/themes/$slug") || { echo "  -> fetch failed for $slug" >&2; continue; }
  if entry=$(parse_theme_page "$slug" "$page"); then
    printf '%s\n' "$entry" >>"$tmp_entries"
  fi
  sleep "$DELAY"
done

jq -s \
  --arg source "$BASE" \
  --arg scraped_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{source: $source, scraped_at: $scraped_at, themes: sort_by(.name)}' \
  "$tmp_entries" >"$OUT_FILE"

echo "Wrote $(jq '.themes | length' "$OUT_FILE") themes to $OUT_FILE" >&2
