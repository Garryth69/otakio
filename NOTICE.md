# NOTICE

Otakio — manga reader for the PS Vita.
Copyright 2026 Garryth69 and contributors. Licensed under the GNU General Public License v3.0 (see `LICENSE`).

Otakio started as a fork of NOBORU and has since been largely rewritten. This file lists the third-party work it
contains or builds on.

## Code

| Component | Author / origin | License | Where |
|---|---|---|---|
| NOBORU | [Creckeryop/NOBORU](https://github.com/Creckeryop/NOBORU) | GPL-3.0 | the app this project was forked from (`source/`) |
| lpp-vita (Lua Player Plus Vita) | [Rinnegatamante/lpp-vita](https://github.com/Rinnegatamante/lpp-vita), NOBORU fork [Creckeryop/lpp-vita](https://github.com/Creckeryop/lpp-vita) | GPL-3.0 | the engine, `source/eboot.bin`; Otakio's changes: `engine/patches/`, fork [Garryth69/lpp-vita](https://github.com/Garryth69/lpp-vita) (branch `otakio`) |
| libvita2d | [xerpi/libvita2d](https://github.com/xerpi/libvita2d), fork [Creckeryop/libvita2d](https://github.com/Creckeryop/libvita2d) | MIT | linked into the engine |
| LuaJIT, curl, OpenSSL 1.1.1, libpng, libjpeg, libwebp, zlib | their respective authors (via VitaSDK / vdpm) | MIT, curl, OpenSSL (dual OpenSSL/SSLeay), libpng, IJG, BSD, zlib | linked into the engine |
| keiyoushi extensions-source | [keiyoushi/extensions-source](https://github.com/keiyoushi/extensions-source) | Apache-2.0 | theme logic adapted to Lua in `source/assets/libs/engines.lua`, `engines_extra.lua`, `engines_intl.lua` (changes: rewritten in Lua for LuaJIT on the Vita, reduced to listing, search, chapters and pages) |

## Fonts and images

| Asset | Origin | License |
|---|---|---|
| `source/roboto.ttf`, `source/robboto.ttf` | Roboto (Google), as shipped by NOBORU with extra glyph coverage | Apache-2.0 |
| Fredoka (`tools/fonts/Fredoka.ttf`), used only to render the title in the logo / LiveArea images | [The Fredoka Project Authors](https://github.com/hafontia/Fredoka-One) | SIL Open Font License 1.1 (`tools/fonts/OFL-Fredoka.txt`) |
| Icons, logo, mascot, button glyphs | drawn by `tools/gen_assets.py` and `tools/gen_buttons.py` for Otakio | GPL-3.0 (this project) |

## Translations

Original NOBORU translations by SamuEDL, theHeroGAC, Rinnegatamante, Samilop Iter, lukrynka and rutantan. The Russian
interface text builds on NOBORU's Russian translation.

## Content

The app ships no manga, comics or images and no content sources. Sources are extensions the user installs from a
repository of their choice (see `README.md`).
