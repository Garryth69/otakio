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
- Crash dumps (`ux0:data/*.psp2dmp`) can be read with `vita-parse-core`.
