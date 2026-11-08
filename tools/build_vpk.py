"""Builds Otakio.vpk from source/ (a VPK is a zip with eboot.bin + sce_sys at the root).

Usage: python tools/build_vpk.py [--skip-checks] [--eboot engine/eboot_tls13.bin] [--name Otakio.vpk] [--with-catalog]
  * release builds carry no extensions: sources come from an extension repository the user adds in the app
  * --with-catalog bundles source/repo/ (the local extension catalog) for offline/test builds
  * writes param.sfo with tools/mksfo.py from VERSION_NAME / TITLE_ID in source/assets/libs/config.lua
  * runs the Lua syntax check before packing
"""
import shutil, argparse, os, re, subprocess, sys, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "source")
OUT = os.path.join(ROOT, "build")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mksfo  # noqa: E402
CONFIG = os.path.join(SRC, "assets", "libs", "config.lua")


def app_config():
    """VERSION_NAME and TITLE_ID from source/assets/libs/config.lua: the single place the version is set"""
    text = open(CONFIG, encoding="utf-8").read()
    version = re.search(r'VERSION_NAME\s*=\s*"([^"]+)"', text).group(1)
    title_id = re.search(r'\bTITLE_ID\s*=\s*"([^"]+)"', text).group(1)  # \b: not UPDATER_TITLE_ID
    return version, title_id


def app_ver(version):
    """"1.0" -> "01.00", "1.1.0" -> "01.10", "1.2.3" -> "01.23" (param.sfo APP_VER is XX.YY)"""
    parts = [int(x) for x in re.findall(r"\d+", version)[:3]] + [0, 0]
    major, minor, patch = parts[:3]
    if minor > 9 or patch > 9:
        sys.exit("version %s does not fit APP_VER XX.YY (minor and patch must be 0-9)" % version)
    return "%02d.%d%d" % (major, minor, patch)


def make_sfo():
    version, title_id = app_config()
    sfo = os.path.join(SRC, "sce_sys", "param.sfo")
    mksfo.write(sfo, "Otakio", title_id, app_ver(version))
    print("param.sfo: %s %s (APP_VER %s)" % (title_id, version, app_ver(version)))
    make_updater(version)


def make_updater(version):
    """Otakio Updater (source/updater/): the helper title that installs updates while Otakio is closed.
    Only index.lua is hand-written; its sce_sys is generated here from the app's own."""
    text = open(CONFIG, encoding="utf-8").read()
    updater_id = re.search(r'UPDATER_TITLE_ID\s*=\s*"([^"]+)"', text).group(1)
    sce = os.path.join(SRC, "updater", "sce_sys")
    os.makedirs(os.path.join(sce, "livearea", "contents"), exist_ok=True)
    mksfo.write(os.path.join(sce, "param.sfo"), "Otakio Updater", updater_id, app_ver(version), stitle="Otakio Updater")
    shutil.copyfile(os.path.join(SRC, "sce_sys", "icon0.png"), os.path.join(sce, "icon0.png"))
    for f in ("template.xml", "bg.png", "startup.png"):
        shutil.copyfile(os.path.join(SRC, "sce_sys", "livearea", "contents", f), os.path.join(sce, "livearea", "contents", f))
    print("updater: %s (APP_VER %s)" % (updater_id, app_ver(version)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-checks", action="store_true")
    ap.add_argument("--eboot", help="engine binary to pack instead of source/eboot.bin")
    ap.add_argument("--name", help="output file name (default: Otakio-<version>.vpk)")
    ap.add_argument("--with-catalog", action="store_true", help="bundle source/repo (test builds)")
    args = ap.parse_args()
    if not args.skip_checks:
        r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "check_syntax.py")])
        if r.returncode != 0:
            sys.exit("syntax check failed")
    make_sfo()
    os.makedirs(OUT, exist_ok=True)
    vpk = os.path.join(OUT, args.name or "Otakio-%s.vpk" % app_config()[0])
    count = 0
    with zipfile.ZipFile(vpk, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for dp, _, files in os.walk(SRC):
            for f in files:
                if f.endswith((".tmp", ".part")):
                    continue
                full = os.path.join(dp, f)
                arc = os.path.relpath(full, SRC).replace("\\", "/")
                if arc.startswith("repo/") and not args.with_catalog:
                    continue
                if arc == "eboot.bin" and args.eboot:
                    full = args.eboot
                # eboot.bin must be stored uncompressed-friendly; deflate is fine for VitaShell
                z.write(full, arc)
                count += 1
        # GPLv3: the license and the README (credits, source code notice) travel with the app
        for doc in ("README.md", "LICENSE", "NOTICE.md"):
            if os.path.exists(os.path.join(ROOT, doc)):
                z.write(os.path.join(ROOT, doc), doc)
                count += 1
    print("catalog:", "bundled" if args.with_catalog else "not bundled (release)")
    print(f"{vpk}: {count} files, {os.path.getsize(vpk) / 1024 / 1024:.1f} MB")


if __name__ == "__main__":
    main()
