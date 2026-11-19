# Rebuilding the engine (lpp-vita)

Otakio runs on **lpp-vita** (Lua Player Plus for the PS Vita), from NOBORU's fork
[Creckeryop/lpp-vita](https://github.com/Creckeryop/lpp-vita) at commit `0ab66ae`. Otakio's changes live in two places:

- `engine/patches/` in this repository: `lpp-vita-otakio.patch`, the added C files and `patch_convertimage.py`;
- the fork [Garryth69/lpp-vita](https://github.com/Garryth69/lpp-vita), branch `otakio`, with the same changes as
  commits. Its `BUILDING.md` has the step-by-step build.

The shipped binary is `source/eboot.bin`. `engine/*.bin` are local build outputs and are not committed.

## What changed and why

| Change | Reason |
|---|---|
| Current VitaSDK (gcc 10.3), LuaJIT 2.1, vdpm libraries | the 2022 toolchain no longer builds; LuaJIT 2.1 ships its own lua-compat |
| libcurl rebuilt against OpenSSL 1.1.1, TLS 1.0–1.3 | many sites refuse TLS 1.2-only clients |
| No forced `User-Agent` header | the engine overrode the script's UA with Chrome 58, and some sites block browser UAs from apps. Lua now sets the UA per request (`net.lua`) |
| Text responses no longer count the trailing NUL | every text body had one extra byte, and strict JSON decoding failed with "trailing data" |
| `Content-Type`/`Content-Length` only on POST, `SCE_O_TRUNC` on downloads | correct GETs; re-downloads no longer leave stale bytes |
| Native WebP (libwebp) | WebP covers and pages without an image proxy |
| `System.convertImage(src, dst, "jpg"\|"png"\|"webp"[, q])` | "Save image" in the reader, at full resolution |
| Zip extraction creates missing parent folders and skips files it can't open | zips without folder entries (common in .cbz) made it write to a NULL file and close the app |
| vita2d per-frame pool of 4 MB instead of 16 MB | the pool is reset every frame; 16 MB kept 12 MB of main RAM idle |
| Release flags `-DSKIP_ERROR_HANDLING -fno-optimize-sibling-calls` | NOBORU's engine was a release build. Without `-fno-optimize-sibling-calls` the new toolchain crashed in `png_read_info` (jump to an unrelocated stub) |
| Arguments copied as plain strings (`snprintf("%s")`), 1 KB path buffers | `sprintf(dst, arg)` read URLs, POST bodies, cookies, headers, paths and dialog text as printf formats: a `%20` in a POST body was mangled, and a URL over 512 bytes overflowed a static buffer next to other engine state. Links keep the app's doubled `%%` (collapsed by the engine) |
| gzip/deflate transfers, 64 KB buffer, TCP keep-alive, 10 min DNS cache | listings and JSON arrive 5-10x smaller; a body a server compressed wrongly is asked again uncompressed |
| One curl share for DNS, TLS sessions, connections and cookies | no new TLS handshake per request; sites that set a cookie on the first visit get it back |
| `Network.getLastResponse([sync])`, `Network.clearCookies()` | HTTP status, curl error, final URL, content type, time, bytes and compression of each request, for retries and the log |
| `OTAKIO_ENGINE` table (`version`, `gzip`, `cookies`, `response`, `plainArgs`, `gif`, `avif`, `filters`, `imageLane`, `htmlNative`, `jsonNative`, `selectNative`, `hashNative`) | scripts use a feature only when the engine has it |
| Image decoding in its own async lane (`Graphics.getAsyncState/getAsyncResult`) | the next page downloads while the current one decodes |
| GIF first frame through stb_image | the old GIF decoder wrote frames without bounds checks and took the app down |
| Native AVIF (libavif 1.4.2 + dav1d 1.5.4 with NEON), straight into the texture at the kept scale | AVIF pages no longer go through the image proxy |
| `Graphics.filterImage(img, "gray"\|"invert")` | grayscale and inverted reader pages, written into the texture once after decoding |
| `HtmlNative.new/parse` (luaHtml.cpp) | the app's HTML tree built in C, in steps; identical to html.lua's parser on real pages |
| `JsonNative.new/decode` (luaJson.cpp) | json.lua's decoder in C, in steps: the same values on real API responses and edge cases, 6-15x faster without the JIT (a 1.2 MB MangaDex list: 84 -> 6 ms on a PC) |
| `HtmlNative.selector`, `HashNative.sha256` (luaSelect.cpp) | html.lua's CSS selector walk in C, in steps, on an index of the tree built once per page: the same results on the real selectors of every source and on generated ones, 10-15x faster without the JIT; and sha256.lua in C |
| `libvita2d-otakio.patch`: font files read through a 2 MB shared block cache | FreeType's default stream made several card reads per new glyph (about 10 ms each with the 13 MB CJK fonts) |

## Automatic build

The fork builds the engine with GitHub Actions on every push to `otakio` (`.github/workflows/build.yml`):
- the same toolchain as the shipped binary: the VitaSDK autobuild of 2025-03-11, gcc 10.3, checked by SHA-256;
- the same vdpm packages, plus libcurl 8.17.0 rebuilt against OpenSSL 1.1.1;
- NOBORU's libvita2d at a fixed commit.

Each run keeps `eboot_unsafe.bin` with its SHA-256 and `build-info.txt` as an artifact. A tag named `engine-*` publishes
them as a release. The output is not byte-identical to a local build, because debug info records the build paths and
the fself is compressed, but it is built from the same source and the same toolchain.

## Quick rebuild (WSL/Linux with VitaSDK)

```sh
git clone -b otakio https://github.com/Garryth69/lpp-vita
git clone https://github.com/Creckeryop/libvita2d && make -C libvita2d/libvita2d
cd lpp-vita && make -j8          # -> eboot_unsafe.bin, copy it to source/eboot.bin
```

Prerequisites (OpenSSL 1.1.1 and the rebuilt libcurl, vdpm packages) are listed in the fork's `BUILDING.md`.
`engine/build_convert.sh` re-applies `System.convertImage` on top of a checkout that only has the older patch.

## Testing a new engine

- `python tools/tests/sim.py browse --online` runs the Lua side against a simulated engine with real HTTP.
  `--tls12` emulates NOBORU's old engine.
- On the console: replace `ux0:app/OTAK00001/eboot.bin` over FTP (keep a backup). Then open a TLS 1.3-only source
  and a WebP source, and use "Save image" in the reader.
- Crash dumps (`ux0:data/*.psp2dmp`): `python tools/parse_crash.py <dump> <lpp-vita.elf.unstripped.elf>`. Every CI
  build keeps that ELF with its symbols (artifact and `engine-*` release); for an older engine, rebuild its commit with
  the same toolchain (the build is reproducible: same eboot hash). The script needs `pyelftools` and the VitaSDK
  binutils on PATH, and a checkout of [vita-parse-core](https://github.com/xyzz/vita-parse-core) (it patches its few
  Python 2 leftovers on the fly).
