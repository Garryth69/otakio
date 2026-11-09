# Changelog

All notable changes to Otakio. Each `## x.y.z` section becomes the notes of the GitHub release with that tag.

## 1.1.4

### Added
- **Tall pages are read by screens.** On a page taller than the screen (a webtoon strip, or a portrait page fitted to
  the width), the page-turn buttons (L/R or the d-pad) and the edge taps first move down the page about one screen at a
  time, keeping a bit of the previous view, and turn the page only once its end is on screen. Going back does the same
  in reverse and lands on the end of the previous page. Before, one press jumped to the next page and the rest of a
  strip was never seen, so pages looked cut. The analog stick and dragging still pan freely; pages that fit the screen
  turn at once, as before.
- `log.txt` gets a line every 30 s with the frames that took over 50 ms, with the screen and what was running (network
  stage, extension job, font warm-up), to find what still stalls.
- Image downloads that fail are logged with the image's host and path (also behind the converting proxy) and what came
  instead of an image (an HTML page, an empty file...).

### Changed
- **Start-up about 10 s faster.** The interface fonts carry the CJK ideograms (13 MB each) and every glyph rendered
  for the first time is read from the memory card, so pre-rendering the whole character set at start-up took about
  10 s. Only the basic Latin set is rendered before the Library appears; the rest is rendered off-screen a few glyphs
  per frame during the first seconds (and timed in `log.txt`).
- **"Save image" no longer freezes the reader.** The page is kept as downloaded by default (new setting value
  *Original*): converting a 5000 px strip to PNG took seconds, and the copy itself is now done in steps over several
  frames. PNG, JPEG or WebP can still be chosen in Settings; the conversion then takes a few seconds. Installs with the
  old PNG default move to *Original* (data version 2); a JPEG or WebP choice is kept.
- `log.txt` lines are appended instead of rewriting the whole file each time: every screen change, chapter opening or
  error rewrote a 30 KB file.
- The network stack stays up 60 s after the last request (2 s before): turning pages or going back to a list after a
  short pause reuses the connections and TLS sessions instead of paying DNS, TCP and TLS again.
- Leaving Browse or the reader, and changing a cover, no longer run a full garbage collection (a visible pause); the
  incremental collector takes care of it.

## 1.1.3

### Fixed
- First-run setup: its last screen no longer offers *Open Extensions*. Choosing it skipped *Install recommended
  sources*, and the setup never came back to offer it. The options are now *Install recommended sources* and *Done*.

### Added
- *Install recommended sources* is also in Extensions → Repositories (Select) while the Otakio extension repository
  isn't added, for whoever skipped it in the setup or removed the repository. Like in the setup, nothing is added
  until it is chosen. It is also offered while no extension is installed, e.g. after a setup done without a
  connection (the repository was added but nothing could be installed).
- *Install recommended sources* tells the cases apart: no connection (try again in Repositories), all recommended
  sources already installed, or none for the chosen languages. Before, all three said "check the connection".

## 1.1.2

### Added
- **Reader settings sheet** (Select while reading, or the menu icon), in Otakio's style, with the page still visible
  beside it:
  - this manga's orientation, direction and scaling;
  - **page colors**, like Mihon: background (theme, black, gray, white), brightness, and a color filter with presets
    (Sepia, Paper, Warm, Night) or your own red/green/blue/opacity, blended as an overlay or multiplied;
  - show page number, double tap to zoom, tap page edges;
  - set the page as cover, save the page.
  It opens at any time while a chapter is open, also while the page is still loading (before, it could not be reached
  until the page had loaded). Select no longer switches the orientation: it is the sheet's first option.
- **Downloads** tab views: *Queue* (downloading now), *Downloaded* (what is on the memory card; Start lists a manga's
  downloaded chapters to delete them one by one) and *History* (finished, failed and canceled downloads, with dates).
  Triangle clears the history; downloaded chapters are kept.
- **Backup before every app update:** library, reading progress, settings and extensions are saved to
  `ux0:data/otakio/backups/otakio_auto_<date>_from-<version>.otk` before the download starts (the last 3 are kept;
  your own backups are never removed). More → Data → *Restore backup* brings them back.
- **Data migrations:** the data on the memory card now has a version (`data_version.txt`). When a future version
  changes a data format, Otakio converts the data at startup, after copying the files to
  `backups/pre-migration-<n>/`; if the conversion fails, the files are put back and the app starts with them as they were.
- **Automatic diagnostics** in `ux0:data/otakio/log.txt`, with nothing to do on the console:
  - internal errors (they only reached the debug overlay before), each repeated message counted instead of repeated;
  - the last screens, dialogs and chapters opened, so the log shows where the app was if it closes;
  - system crash dumps that appeared since the last session;
  - free RAM/GPU memory when it changes a lot, and how long each step of the start-up took.

  Nothing is sent anywhere, and log lines are cleaned: URLs lose their query strings; e-mail and IP addresses, tokens,
  cookies and passwords are removed.
- Theme picker shows each theme's colors and previews the theme under the cursor (Circle goes back).
- App updates show a progress panel: download bar with MB, percent, speed and time left (Circle cancels), then the
  unpacking and installer steps. Otakio Updater shows its steps too.
- Every update step is timed in `ux0:data/otakio/log.txt`.

### Changed
- **The same buttons do the same things on every screen:** Triangle refreshes (Library, Updates) or searches
  (Browse, catalogs, Extensions); Square switches tabs (Library categories, Extensions, Downloads); Start opens the
  screen's or the item's options. In Updates, Triangle now refreshes and Start opens the manga's details (the other
  way round before); in History, Start opens the details. Button hints are listed in the same order everywhere.
- Help texts show button icons, the same as the hint bar, instead of words in each language ("Square", "Quadrado"...).
  With the Japanese button layout the confirm/back icons follow the swap.
- Downloads: the Queue / Downloaded / History chips sit under the title like the other tabs; Square switches them and
  Start opens the selected manga's or entry's options.
- Updates and History rows use the same text styles as the other lists.
- The "connection lost" message is a card in the theme's colors.
- Otakio Updater uses the app's font (Roboto, cut down to 22 KB) and theme colors instead of the engine's debug font.
- The reader's top and bottom bars follow the theme.
- Themes: clearer cards on Light, a more visible selection on Dark, visible dividers on AMOLED, darker secondary text
  on Sakura, and Crimson's "delete" color no longer matches its accent.
- **Adaptive clocks:** the console runs at 444 MHz (CPU) / 222 MHz (GPU) while something happens (input, loading,
  downloads, extension jobs, updates) and goes back to the default 333/166 MHz after a few seconds without activity,
  e.g. while reading a page: the same speed when it matters, less battery and heat.
- Engine: 12 MB more free RAM (the per-frame drawing pool is 4 MB instead of 16 MB).
- Faster start-up: the full character set is pre-rendered only for the three font sizes most of the interface uses.
- Faster app updates: shorter fixed waits in the app and in Otakio Updater.
- If an update can't be installed inside the app, the VPK is now kept in `ux0:data/otakio/vpk/` (install it with
  VitaShell). It is removed after the next successful update.

### Fixed
- **GPU crashes:** textures could be freed in the middle of drawing a frame (by the code or by Lua's garbage
  collector) while the GPU was still going to read them. Textures are now freed only between frames, when the GPU is
  idle. The error barrier also closes a half-drawn frame correctly (its draw-phase flag was never set).
- Engine: extracting a zip without entries for its folders (common in .cbz files) wrote to a file that failed to
  open and closed the app. The engine now creates the missing folders and skips a file it still can't write.
- Browse offered languages turned off in *Source languages* (Start and More → Browse → language), and a language
  turned off later stayed selected. Only active languages are offered now, and an inactive one goes back to all.
- Browse's language filter now lists every language chosen in *Source languages*, also one without a source of its
  own: multi-language sources serve it. Before, with Portuguese and English chosen but only
  multi-language and English sources installed, it offered just "All languages" and English.
  - *Portuguese* now shows both Brazilian and European Portuguese sources.
  - The chosen filter is kept after restarting the app. It always went back to "All languages", because it was
    checked before the chosen languages were loaded.
  - Multi-language extensions can list titles in the filter's language (`BrowseLanguageIsos()`); before, they could
    only follow the interface language.
- Extensions with one source per language (for example English, Spanish, French and German):
  - opening one could show another language's titles. The background source check shared its preloaded list
    between all the sources of an extension, so the English source could show the Spanish or German list. Each
    source now keeps its own list;
  - in Extensions they appear only under their languages (no longer under a language they don't have), and the
    row shows them ("en/es/fr/de");
  - "Open source" opens the one in the selected language chip or the Browse language, else one in an active
    language (English first), always the same one. Before, it was a random one;
  - the first-run "Install recommended sources" skips them when none of their languages is active.
  Extensions can declare this with a `-- @langs en,es` header (`langs` in `index.json`).
- Large downloads on slow Wi-Fi were stopped after 90 seconds and started over from zero. A download is now stopped
  only when no data arrives for 30 seconds.
- A retried download had no deadline at all and could hang the download queue.
- On first run, the app update prompt could take the place of the setup's last screen: accepting it skipped
  *Install recommended sources*, so the app came back with no repository. The prompt now waits for the setup and for
  extension installs to finish.
- In-app update crashed while unpacking the new version: the engine's extractor can't create folders that have no
  entry of their own in the VPK. Release VPKs now list every folder, and the app creates them before extracting.

## 1.1.1

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
