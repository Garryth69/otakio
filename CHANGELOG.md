# Changelog

All notable changes to Otakio. Each `## x.y.z` section becomes the notes of the GitHub release with that tag.

## Unreleased

### Fixed
- In-app updates now install for real: the Vita can't reinstall an app that is running, so Otakio hands the
  downloaded package to *Otakio Updater*, a small helper that installs it while Otakio is closed, then reopens
  Otakio and is removed. Every step is written to `ux0:data/otakio/log.txt`.

## 1.1.0

### Added
- **In-app updates:** a new release is downloaded, checked (size, Otakio's title id), installed with the system
  installer and the app restarts. More → About → *Check for app updates at startup* turns the automatic check off.
  If installing inside the app fails, the VPK is left in `ux0:/vpk/` for VitaShell.
- Interface in Russian, Japanese and Chinese (Simplified and Traditional), with CJK-aware text wrapping.
- First-run setup:
  - covers app language, active source languages, adult content, reading direction, orientation, confirm button and
    theme;
  - its last screen offers **Install recommended sources**, which adds the Otakio extension repository and installs
    Otakio's own sources for the chosen languages.
- **Active languages** (More → Browse / Extensions): only the chosen languages appear as tabs in Extensions and in Browse.
- Extension safety:
  - every file in the official repository is pinned by SHA-256 in `index.json`, and a download that doesn't match is
    refused;
  - extensions run in a sandbox (no file system, `io`, `os` or module loading; read-only settings);
  - adding a third-party repository asks for confirmation.
- Manual extensions: `.lua` files copied to `ux0:data/otakio/extensions/manual/` load at startup, labelled *Manual*.
- Extensions removed from their repository are labelled *Removed from repository* (they keep working until uninstalled).
- New source engines for Russian, Japanese and Chinese sites (Grouple, LibGroup, MultiChan, FMReader, NatsuId,
  MangaReader, Liliana) and adult galleries (GalleryAdults).

### Fixed
- Text split into lines always gained an extra trailing newline.
- *Open source* and status tracking for Otakio's native extensions (their parsers lost the extension id).
- Five extensions whose published file didn't match the SHA-256 in the catalog (line endings) and were refused on install.

### Changed
- Faster page and cover loading:
  - the page you open is downloaded before the pages prefetched after it (first page shows up sooner);
  - covers scrolled away and back in Browse are read from disk instead of downloaded again (in a test: 251 requests
    instead of 1297, 6 MB instead of 27 MB);
  - opening a title reuses the cover already downloaded in Browse;
  - opening a source right after startup reuses the list the status check just downloaded.
- Faster text handling: the UTF-8 aware `string.sub` takes a fast path for plain ASCII text (about 5x faster, same
  results), which speeds up the classic NOBORU parsers.
- New app icon (centered inside the Vita's round bubble) and logo; LiveArea reorganized around the start gate;
  consistent button glyphs in the hint bar and dialogs.
- The HTML parser no longer loses the rest of a page after a malformed attribute with a stray quote.
- Cache, library and download folder names are ASCII-safe for non-Latin titles.
- `param.sfo` is written by `tools/mksfo.py`, and the version comes only from `config.lua`.
- Release VPKs come with a `.sha256` file.

## 1.0

First public version: library with categories, reader, offline downloads, `.cbz`/`.zip` import, backups, extension
repositories with live status dots, native TLS 1.3 and WebP engine, interface in six languages.
