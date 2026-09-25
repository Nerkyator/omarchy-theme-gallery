# Theme Gallery

An [Omarchy](https://omarchy.org/) shell plugin that browses community themes
from [omarchythemes.com](https://omarchythemes.com/) and installs one with a
click — no copy-pasting a git URL into `omarchy theme install`.

![Theme Gallery screenshot](screenshot.png)

## What it does

- Scrapes the public theme listing at omarchythemes.com into a local catalog
  (name, author, preview, source repo).
- Shows it as a searchable grid inside the Omarchy shell (`panel` plugin —
  same family as the built-in Speed Test / Wi-Fi QR panels).
- Clicking **Install** runs `omarchy theme install <repo>` for community
  themes, or `omarchy theme set <name>` for the handful of official themes
  that are already bundled with Omarchy.
- Clicking **Refresh** re-scrapes the site and re-downloads thumbnails, so
  the catalog stays current without touching a terminal.

This is an unofficial, community tool. It isn't affiliated with Omarchy or
omarchythemes.com, and it doesn't ship any of their content — the catalog and
thumbnails are fetched fresh, on your machine, the first time you hit
Refresh.

## Install

```sh
omarchy plugin add https://github.com/Nerkyator/omarchy-theme-gallery.git --enable
```

Then open it from the Omarchy menu — **Style → Theme Gallery** — or run:

```sh
omarchy-shell shell summon io.github.nerkyator.theme-gallery '{}'
```

On first run the gallery is empty; click **Refresh** to fetch the catalog
(a few minutes — it's a polite, rate-limited crawl of ~290 theme pages, see
[Why Refresh is slow](#why-refresh-is-slow) below). After that it's instant,
reading from `~/.cache/omarchy-theme-gallery/catalog.json` and cached
thumbnails next to it in `thumbs/`.

## Remove

```sh
omarchy plugin remove io.github.nerkyator.theme-gallery
```

This deletes the plugin's own folder. It never touches any theme you
installed through it — those live under `~/.config/omarchy/themes/` like
any other theme and are removed with `omarchy theme remove <name>`,
independently, if you want them gone too. The cached catalog and thumbnails
live separately at `~/.cache/omarchy-theme-gallery/` (see below) and aren't
cleaned up automatically; delete that directory too if you want a full
removal.

## How it's built

```
manifest.json           Omarchy plugin manifest (kind: panel)
Panel.qml                The gallery UI (Quickshell/QML)
scripts/
  scrape-catalog.sh       Rebuilds catalog.json from omarchythemes.com
  cache-thumbnails.sh      Downloads each theme's preview image locally
  refresh.sh               Runs both of the above — what the Refresh button calls
```

The catalog and thumbnails are cached at `~/.cache/omarchy-theme-gallery/`,
deliberately **not** inside this plugin's own folder. Omarchy watches every
installed plugin's directory recursively to hot-reload it on code changes;
writing a catalog.json and ~290 thumbnails under the plugin's own folder on
every Refresh was indistinguishable from "the plugin's code changed" and
force-closed the panel mid-refresh. Caching outside `~/.config/omarchy/plugins/`
avoids that entirely.

`scrape-catalog.sh` identifies itself with a descriptive User-Agent and waits
between requests (default 0.4s) — see the script for `--delay`/`--limit`
flags if you want to tune that.

## Why Refresh is slow

omarchythemes.com has no public API — Refresh works by scraping its HTML
(the listing page, then every individual theme page, one polite request at
a time with a delay between them so it doesn't hammer the site). That's
what makes a full Refresh take a few minutes instead of a few seconds. If
the site ever exposes a real API, swapping it in would make this dramatically
faster.

This is also why there's no "sort by stars" or "sort by most recently
updated": that data lives on GitHub, not on omarchythemes.com, and getting
it would mean an *additional* API call per theme (~290 of them) against
GitHub itself. Unauthenticated, GitHub's API allows 60 requests/hour — so a
single pass would take roughly 5 hours. It's technically possible with a
personal access token (GitHub's GraphQL API can batch dozens of repos per
request), but that's a deliberate scope cut for now rather than a
limitation of the idea. Sorting by **name** doesn't have this problem —
that's already in the catalog — and is the only sort option today.

## Known limitations

- The catalog is a point-in-time snapshot; hit Refresh to update it.
- omarchythemes.com has no public API, so this scrapes its HTML. If the site
  changes its markup, `scrape-catalog.sh` may need updating.
- A handful of "official" Omarchy themes on the site link to the Omarchy
  manual instead of a repo; those show an **Apply** button (`omarchy theme
  set`) instead of **Install**.

## License

MIT — see [LICENSE](LICENSE).
