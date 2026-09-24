#!/bin/bash
# Rebuilds the local catalog (scrape + thumbnails). This is what the panel's
# "Refresh" button runs; also handy standalone after installing the plugin,
# or periodically via `omarchy hook install` if you want a cron-like refresh.
#
# Usage: refresh.sh [scrape-catalog.sh args, e.g. --limit N --delay SECONDS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/scrape-catalog.sh" "$@"
"$SCRIPT_DIR/cache-thumbnails.sh"
