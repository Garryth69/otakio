# Changelog

All notable changes to Otakio. Each `## x.y.z` section becomes the notes of the GitHub release with that tag.

## 1.1.5

### Added
- **Site themes fixed without an app update:** when a theme used by many sources (Madara, MangaThemesia, Keyoapp...)
  changes its pages, the official catalog can publish a fix for its engine. The app downloads it on the next catalog
  refresh (its SHA-256 checked), runs it in the extension sandbox and rebuilds the installed sources on top of it.
- **Remote settings:** the browser identification sent to sites, the image converter, extensions to switch off and a
  one-time notice can be changed from the project's GitHub (remote.json) without a new version of the app.
- **New engine (network):** pages, lists and searches arrive compressed (5-10x less data); connections, TLS
  sessions and DNS answers are reused between requests, so a site is reached without a new handshake; cookies a
  site sets are sent back to it during the session (some sources only list chapters to a visitor that has one).
  *Clear all cache* also forgets them.
- **Pages download while the previous one decodes:** images have their own lane in the engine, so the reader no
  longer waits for one to finish before asking for the next.
- **AVIF and GIF without the proxy:** AVIF pages and covers are decoded on the Vita itself, and GIFs show their first
  frame (the old GIF decoder could close the app).
- **Grayscale and inverted pages** (reader settings > Pixels).
- **Page buttons in webtoon mode** (Settings > Controls): they now jump to the next or previous page, like in the other
  reading modes; *Scroll* keeps the old behavior (a screen at a time).
- **Faster lists:** the HTML of listings and chapters is read by the engine (in C) instead of Lua, still a piece at a
  time so the screen keeps moving.
- **JSON read in C too:** sources with an API (MangaDex, MangaFlix, Asura, MangaLib...) and the extension catalog are
  decoded by the engine, 6-15x faster than before, with exactly the same result.
- **Pages searched in C:** after a page is read, finding its covers, titles, chapters and images (the CSS selectors
  every source uses) runs in the engine on an index of the page, 10-15x faster than the Lua walk, with exactly the
  same results. Extension downloads are checked (SHA-256) in C as well.
- **Text appears faster:** the interface fonts are read from the memory card through a cache, instead of several card
  reads for every new character (they were the slowest part of start-up and caused a long stutter right after it).
- **Clearer log:** every 30 s, requests per site (count, average time, size, compression, failures); a request that
  fails or comes back empty is logged with its address and HTTP status. Images that a site refuses (404, 403) are
  not asked again three times.

- **Source settings** (Square in a source, at the bottom of the panel): the site's address can be changed when a site
  moves (every request, Referer included, goes to the new one; empty goes back to the default), and extensions can
  declare their own options (`Preferences`, read with `self:pref(key)`).
- **Sites that move to a new address keep working:** the daily check notices when a site's address now leads to
  another domain, tests the extension there, and the catalog says where it went. The app sends that source's requests
  to the new address by itself (no extension update needed); an address set by hand in the source settings wins, and
  the panel shows the automatic one.
- **Filters are remembered per source** and come back the next time; *Reset filters* brings the defaults back.
- **Genres filter for Madara sources** (about 170): the genre list is read from the site the first time it is opened.
- Filter names and common values (Sort by, Status, Completed...) are shown in the interface language.
- The source panel follows the theme like the other side sheets.
- **Extensions say where a source stops**, next to its status: *site blocks apps*, *list doesn't load*, *no
  chapters*, *chapters without pages* or *images blocked* (from the daily check of every source).

### Changed
- **Opening a result of the global search is fast:** its chapters go first in line, and the sources still being
  searched step aside (they finish afterwards). Before, the chapters waited behind every source's search.
- **A slow background download no longer holds up what you asked for:** a cover that takes several seconds is paused
  and resumed later when a list or chapter you opened is waiting.
- **Smoother while sources load:** big JSON lists (MangaFlix, MangaDex...) and the extension catalog are read in
  smaller steps, and the log is written to the card in batches instead of line by line (start-up is lighter too).
- While the system keyboard opens, the screen shows what is being typed for and a spinner instead of going blank.
- Keyoapp sites on the new platform (Kitsune Dawn...) can be searched again.
- **Settings are easier to find:** *Controls* sits right after *Reader*, *Chapter order* moved to *Library*, and the
  active source languages are set in one place (*Browse*). Going back from a section keeps the cursor on it.
- "1 repository" / "1 category" instead of the plural.
- **History tab is smooth with long series:** it reads one title's chapter list from the card per frame instead of
  all the visible ones at once (a screen of 1000-chapter series froze it for most of a second).

### Fixed
- **Without a connection the extension catalog is no longer empty:** the last copy kept on the card is used (also
  when the network is up but GitHub can't be reached), and the update check no longer logs an error.
- **Reader:** preparing the next chapter could close the reader with an error, and the screen could dim and sleep while
  reading. Both features read system functions that the extension sandbox had already removed.
- **Sources:** Siren Scans and Asmodeus Scans work again: their sites moved to a new version of the Keyoapp theme,
  which the app now supports. Tower of God Manga Online lists its 650+ chapters again. Mist Scans follows its new
  domain. Mangakakalot works again on its mirror (its old address now leads to another site). MHScans and KeroScans
  moved to sites of their own and now have native extensions; installed copies are replaced automatically.
- **POST requests with `%` in their body** (most searches sent as a form) reached the site mangled; very long
  addresses (over 512 characters, common behind the image proxy) overwrote engine memory, a likely cause of rare
  crashes.
- A broken zip no longer closes the app when it is opened.
- Chapter lists still waiting to be written are saved before the cache is cleared, NOBORU data is imported or the app
  restarts to install an update (they could be lost, or bring a cleared folder back).
- Images that turn out to be a web page (a "not found" page sent as an image) are no longer sent to the converting
  proxy and retried: they fail at once.
- Network errors in the log carry curl's error code (its text could name a harmless certificate notice instead of
  the real cause).
- Removed unused code (13 functions, including a busy-wait that could freeze the app) and 2 unused images.
- **Madara sites with their own card design** (Aqua Manga, Cocomic...) list their series again: when none of the
  known card layouts is found, any link to a series page with a cover next to it is a result (menus, sliders and
  sidebars left out); readers that number their page images are read too.
- **Keyoapp sites on the new reader** (Art Lapsa, Kitsune Dawn, Rithar Scans): pages load again.
- **Images on another server** get only the site's address as Referer, like a browser does: several sources
  whose image server refused the full chapter address load again (KunManga, TopManhua, ZazaManga, ZinManga...).
- **More Madara layouts**: the paged reader's page list (`chapter_preloaded_images`), skins with their own chapter
  rows and their own reader (Manhwa-Online, CartoonPorn).
- **MangaLib**: pages load again (its default image server stopped resolving outside Russia); SlashLib keeps the
  server that works for it.

### Sources
- 271 of 363 sources work end to end (251 of 353 in 1.1.4), several thanks to native AVIF/GIF and the POST fix.
- **The catalog looks after itself:** every week it follows keiyoushi (new domains, sources removed upstream), adds
  new sources that pass a live test, and drops sources dead for 90 days. 18 new sources came in this way so far.
- Weeb Central (1000+ chapter series) and Flame Comics (whole catalog in one page) no longer stutter while loading.
- **New native extensions** replacing broken NOBORU parsers: HeavenManga (es), InManga (es), MyHentaiGallery (en),
  VerComicsPorno (es). Installed NOBORU copies are swapped for them automatically.
- Removed 2 NOBORU sources whose domains are now parked pages (Leomangas, ReadM).

## 1.1.4

### Added
- **Touch in the reader:** the bars (title, pages, menu) open with a press held still for about half a second, with
  a ring filling under the finger; a quick tap, a drag or a pinch never opens them, so scrolling and zooming don't
  bring them up by mistake. With the bars shown, a quick tap on the page closes them. A double tap zooms only with two
  quick taps in the same spot, small finger shakes no longer start a drag, and in webtoon mode a fling follows the
  finger's last movements and stops if the finger rested before lifting.
- **Two fingers no longer throw the page:** adding or lifting a finger (a pinch, or a second finger landing while
  scrolling) used to count as a jump of the first one, which sent the page flying; now it starts a new movement and a
  pinch never ends in a fling.
- **An image that failed for good isn't asked again** in the same session (a cover refused by its site was downloaded
  and refused on every screen it appeared on); a page's *try again* in the reader still asks.
- **Source lists stutter less:** the HTML and JSON parsers give the frame back about twice as often.
- **Diagnostics:** a long frame now names the step that took the time (network, parser, screen update, draw, GPU...),
  and the engine's network calls are timed.
- **The next chapter is ready sooner:** near the end of a chapter its page list is asked to the source and its first
  two pages downloaded, so opening it doesn't wait.
- **Huge pages load faster:** a page far bigger than the screen (2500 px raws and up) is decoded at half or a quarter
  of its size, never under 1000 px on its shorter side: a fraction of the memory and a faster decode.
- **Good neighbour:** at most one request every 300 ms to the same site; requests for other sites go meanwhile.
- **Interface text size** (Settings > Other): Normal, Large or Larger text in lists, menus and descriptions.
- **Global search by touch:** drag up and down through the sources and sideways through one source's covers, with
  inertia, like the other screens; the view stays where the finger left it until a button is pressed.
- **Lighter start-up:** the extension catalog is merged without a search per entry (the online index on top of the
  built-in one compared every entry with every other) and gives the frame back as it goes; an index downloaded in
  the last 3 hours is read from the card at start-up (the Extensions tab and a manual refresh still download).
- **Extensions can ask for a newer app:** `-- @api N` in an extension's header (or `"api"` in the index) keeps it out of
  the catalog of an older Otakio, and an installed copy says it needs a newer Otakio instead of failing mid-search.
- **More sources work:** the Madara engine reads the newer card skin (`.manga-hover-card`, title from the link) and
  opens a "chapter" that is a link straight to its image as a one-page chapter; the FoOlSlide engine reads the
  `series_element` skin and its `group_comic` chapter lists.
- **Turning pages waits less:** the next page starts loading as soon as you turn (not when the turn animation ends),
  ahead of covers and source work, and the page just left stays decoded while memory allows, so going back is instant.
- **A page that fails to load says so** (instead of loading forever): *Press X to try again*, also from the menu's
  reload icon.
- **The screen stays on while reading** (where the engine allows it): no dimming or sleep in the middle of a chapter.
- **Diagnostics:** the log notes every 30 s how long pages took to show up (average, worst, how many were ready).
- **Webtoon mode:** a new reading direction, *Webtoon (continuous)*, for the whole app (first-run setup, Settings) or
  for one title (reader settings sheet). The chapter's pages sit one under the other and the view scrolls over them,
  like on the sites: the sticks and the d-pad scroll, L/R (or a tap on the top/bottom edge) glide one screen,
  dragging scrolls with inertia, Triangle/Square, the right stick or a pinch zoom in (up to 3x) or out (down to 40%,
  to see more of the strip). It follows the Orientation setting: in *Vertical*, with the Vita held upright, the strip
  fills the 544-pixel width and the controls turn with it.
  Leaving a chapter keeps the exact spot inside the page (not just the page) and the title keeps its zoom; a double
  tap zooms in on that point (2x) or back to the screen width. Scrolling on past
  the end (or pressing R there) opens the next chapter; past the top, the previous one, at its end. Pages load ahead
  of the view and are freed behind it, and a page that loads above the view doesn't move what is being read.
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

### Fixed
- **`string.sub` follows Lua's rules.** Otakio's UTF-8 `string.sub` (inherited from NOBORU) read the third argument
  as a count of characters and ignored negative values, so an extension written in plain Lua got the whole string
  from `s:sub(1, -2)`: 9Hentai covers were asked with a double slash and never shown. It now behaves like Lua's,
  counting characters instead of bytes; nothing in the app or the catalog depended on the old reading.
- Asura Scans chapters open again: the pages come from the site's public API (the chapter page was sometimes refused
  and its script data changed), with the page itself as a fallback.
- The time the system keyboard is open (searches, repository address, connection timeout) no longer counts as a
  5-11 s "hitch" in the `log.txt` report; those were the only long hitches in the logs.

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
- The network stack stays up for the whole session. It was closed 2 s after the last request and brought up again
  (a synchronous engine call) on the next one, which paused the app after every short pause and dropped the open
  connections and TLS sessions; the time the engine takes to bring it up is now in `log.txt`.
- Extensions give the frame back more often while reading a page's HTML (every 16 KB instead of 64 KB), and the time
  of every long step of an extension, extension job or download task goes to the `log.txt` report.
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
