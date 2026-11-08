# Changelog

All notable changes to Otakio. Each `## x.y.z` section becomes the notes of the GitHub release with that tag.

## Unreleased

### Added
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

### Changed
- New app icon and logo; consistent button glyphs in the hint bar and dialogs.
- The HTML parser no longer loses the rest of a page after a malformed attribute with a stray quote.
- Cache, library and download folder names are ASCII-safe for non-Latin titles.
- `param.sfo` is written by `tools/mksfo.py`, and the version comes only from `config.lua`.
- Release VPKs come with a `.sha256` file.

## 1.0

First public version: library with categories, reader, offline downloads, `.cbz`/`.zip` import, backups, extension
repositories with live status dots, native TLS 1.3 and WebP engine, interface in six languages.
