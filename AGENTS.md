# Maintaining Otakio: guide for AI agents and new maintainers

Otakio is a manga reader for the PS Vita. Read this file before changing anything; it sums up how the project works
and the rules that keep it healthy. The README covers usage, `docs/EXTENSIONS.md` covers writing sources and
`docs/ENGINE_REBUILD.md` covers the engine.

## The three repositories

| Repository | What it holds | Branch |
|---|---|---|
| `Garryth69/otakio` (this one) | the app (Lua in `source/`), the prebuilt engine `source/eboot.bin`, tools, tests | `main` |
| `Garryth69/otakio-extensions` | the source catalog: `index.json`, `extensions/`, `native/`, `health.json` | `main` |
| `Garryth69/lpp-vita` | the engine (C/C++, LuaJIT, VitaSDK), a fork of lpp-vita | `otakio` |

Locally the extension repository is cloned into `repo/` inside this one (ignored by git): the tools read and write it
there.

## Rules

1. **Ask before publishing.** Don't push, tag, create releases or merge without the maintainer's explicit OK.
2. **Everything on GitHub is in English:** code, comments, commits, docs, release notes.
3. **No personal data in any commit:**
   - no names, emails or home paths;
   - no LAN addresses (the console's FTP address lives only in the maintainer's local scripts).

   Commits use the account's GitHub noreply email.
4. **Never work around protections:**
   - no Cloudflare or captcha solving;
   - no logins, paid-chapter unlocking or hotlink bypasses;
   - no rotating API keys.

   A protected site stays marked as down.
5. **Release VPKs bundle no extensions.** Users add the catalog themselves; only test VPKs use `--with-catalog`.
6. **Test on the console after every step.** Build a test VPK and give it to the maintainer to install. The PC
   simulator doesn't catch everything (memory, GPU, real network).
7. **When porting work from Lua to C, prove it equal first.** Run the C and Lua versions side by side on real data
   (the engine's host harnesses) and switch only when every result is identical.
8. **Keep the Lua fallback.** The app must still run on an older engine and in the simulator. Check a feature flag
   (`OTAKIO_ENGINE.*`, `HtmlNative`, `JsonNative`...) before using an engine feature.

## Everyday commands (Python 3 with `lupa` and `pillow`; run from this repository's root)

| Task | Command |
|---|---|
| Lua syntax | `python tools/check_syntax.py` |
| Unit tests | `python tools/run_lua.py tools/tests/test_core.lua tools/tests/test_remoteconfig.lua ...` (see `.github/workflows/ci.yml` for the full list) |
| Simulator (whole app, headless) | `python tools/tests/sim.py <scenario>`, e.g. `tour`, `extensions`, `settings`; `--online` uses the real network |
| Translations | `python tools/check_lang.py` |
| Test one source | `python tools/probe_sources.py --ids <file>` or `--file repo/native/x.lua`; `python tools/trace_source.py <id>` prints every request |
| Catalog check | `python tools/validate_repo.py` |
| Build a VPK | `python tools/build_vpk.py --name Otakio-X.Y.Z-testN.vpk [--with-catalog]` |
| Read a console crash | `python tools/parse_crash.py <psp2core file>` (needs the engine ELF) |

Everything in CI (`.github/workflows/ci.yml`) must pass before a change is done.

## How the pieces fit

- `source/main.lua` loads the libraries in `source/assets/libs/` and then **replaces `System` with a reduced table**,
  so extensions can't touch files. A library that needs `System.x` later must read it into a local at load time
  (`tools/tests/test_system_sandbox.py` enforces this).
- `net.lua` holds the single network and image queue, with priorities, deadlines and preemption. `parserhandler.lua`
  runs source jobs in coroutines. Every long loop must yield.
- `extensions.lua` installs, updates and sandboxes the extensions. `REPLACED_BY` moves installs of a retired extension
  to its replacement.
- Engine patches: the official catalog can list Lua files (`patches` in `index.json`) that replace or wrap
  `Engines.*` functions. The app runs them in the extension sandbox before any extension; sha256 pinned, limited to
  `minApp`..`maxApp`, removed when the catalog stops listing them (`extensions.lua`, `tools/add_patch.py`).
- `remoteconfig.lua` reads `remote.json` from this repository at start, which lets the app be adjusted without a
  release (user agent, image proxy, disabled extensions, a notice). The README documents the format.
- Engines for site themes (Madara, MangaThemesia, Keyoapp, ...) live in `engines*.lua`. An extension is either a theme
  configuration or a native parser (see `docs/EXTENSIONS.md`).

## The catalog runs itself (otakio-extensions workflows)

- **`health.yml`, daily:** probes every source with this repository's engines and writes `health.json` and
  `index.json`. It records domain moves (`movedTo`), which the app follows without a new extension version.
- **`regen.yml`, weekly:**
  - follows keiyoushi through `tools/prune_repo.py`: domain changes after a live probe, upstream removals;
  - removes non-keiyoushi sources dead for 90 days, at most 8 a week;
  - adds new keiyoushi sources that pass a live test, through `tools/add_sources.py`;
  - brings keiyoushi's fixes to sources that don't work here, through `tools/update_sources.py`: regenerated from
    their current code and kept only when a live test does better (working sources are never touched).

  It commits to `main`. Safety limits hold back anything unusual: more than 8 upstream removals, a broken clone, or a
  third of the catalog dead at once. `sync.json` records each run.
- **`status.yml`, weekly and when a robot fails:** rewrites the pinned *Catalog status* issue. It also makes a
  keepalive commit after 30 quiet days, because GitHub stops schedules after 60.
- **Dependabot updates** (the pinned actions in all three repositories, the Python packages in
  `tools/requirements.txt`) merge themselves when CI passes, major versions too. The catalog's CI also dry-runs the
  robots' tools, so an update that breaks them is never merged.

Start every maintenance session by reading the *Catalog status* issue.

## Fixing a broken source

1. Find why with `python tools/trace_source.py <id>`.
   - **Cloudflare or a "checking your browser" page:** protected. Leave it.
   - **Site gone:** the 90-day rule removes it.
   - **Layout or theme changed:** look at keiyoushi's current code for that site
     (`keiyoushi/extensions-source`, `src/<lang>/<name>`, and `lib-multisrc/<theme>` for themes).
2. Fix it in the smallest place:
   - a theme engine in `engines*.lua`, when a whole theme changed. Engine changes only reach users with a release,
     so also publish the fix as an **engine patch** (`python tools/add_patch.py repo/patches/<name>.lua --max-app
     <current version>`; the docstring has an example). Installed apps download it on their next catalog refresh,
     and the health check applies it too. Withdraw it with `--remove` if it misbehaves;
   - the generator `tools/gen_repo.py`, when the generated configuration is wrong;
   - a new native in `repo/native/`, when the site left its theme. Add a `REPLACED_BY` entry and retire the old id
     with `tools/remove_sources.py`.
3. When an extension file changes, raise its `version` and re-pin its `sha256` in `index.json`. The app refuses any
   file whose hash doesn't match. Re-probe it, run `python tools/gen_repo_readme.py`, then commit in `repo/`.
4. Engine changes (`engines*.lua`) ship with the app; until the next release, an engine patch carries them (step 2).

## Releasing a version

1. Finish the `CHANGELOG.md` section, and bump `VERSION`/`VERSION_NAME` in `source/assets/libs/config.lua`.
2. If the engine changed:
   - tag the fork (`engine-YYYY.MM.DD`) so its CI publishes the build;
   - put the engine into `source/eboot.bin`;
   - regenerate `engine/patches/lpp-vita-otakio.patch`. The GPL requires the published source to match the binary
     (see `docs/ENGINE_REBUILD.md`).
3. With the maintainer's OK, tag `vX.Y.Z` and push it. The release workflow builds the VPK, and installed apps offer
   the update.

## Never

- force-push, rewrite published history, or delete releases;
- commit `repo/`, build outputs, engine binaries other than `source/eboot.bin`, or local helper scripts;
- add a source that needs an account, payment or a protection bypass;
- remove the Lua fallbacks or the extension sandbox;
- merge the catalog with removals you haven't looked at, when the robots held them back.
