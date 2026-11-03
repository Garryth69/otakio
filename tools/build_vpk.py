"""Builds Otakio.vpk from source/ (a VPK is a zip with eboot.bin + sce_sys at the root).

Usage: python tools/build_vpk.py [--skip-checks] [--eboot engine/eboot_tls13.bin] [--name Otakio.vpk] [--with-catalog]
  * release builds carry no extensions: sources come from an extension repository the user adds in the app
  * --with-catalog bundles source/repo/ (the local extension catalog) for offline/test builds
  * regenerates param.sfo when vita-mksfoex is available (NOBORU ships one)
  * runs the Lua syntax check before packing
"""
import argparse, os, subprocess, sys, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "source")
OUT = os.path.join(ROOT, "build")
TITLE_ID = "OTAK00001"
APP_VER = "01.00"
MKSFO = [os.path.join(ROOT, "tools", "vita-mksfoex.exe"), os.path.join(ROOT, "..", "_ref", "NOBORU", "vita-mksfoex.exe"), "vita-mksfoex"]


def make_sfo():
    sfo = os.path.join(SRC, "sce_sys", "param.sfo")
    for exe in MKSFO:
        try:
            subprocess.run([exe, "-s", "TITLE_ID=" + TITLE_ID, "-s", "APP_VER=" + APP_VER, "Otakio", sfo], check=True, capture_output=True)
            print("param.sfo generated with", exe)
            return
        except (OSError, subprocess.CalledProcessError):
            continue
    if not os.path.exists(sfo):
        sys.exit("vita-mksfoex not found and no param.sfo present")
    print("using existing param.sfo")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-checks", action="store_true")
    ap.add_argument("--eboot", help="engine binary to pack instead of source/eboot.bin")
    ap.add_argument("--name", default="Otakio.vpk")
    ap.add_argument("--with-catalog", action="store_true", help="bundle source/repo (test builds)")
    args = ap.parse_args()
    if not args.skip_checks:
        r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "check_syntax.py")])
        if r.returncode != 0:
            sys.exit("syntax check failed")
    make_sfo()
    os.makedirs(OUT, exist_ok=True)
    vpk = os.path.join(OUT, args.name)
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
        for doc in ("README.md", "LICENSE"):
            if os.path.exists(os.path.join(ROOT, doc)):
                z.write(os.path.join(ROOT, doc), doc)
                count += 1
    print("catalog:", "bundled" if args.with_catalog else "not bundled (release)")
    print(f"{vpk}: {count} files, {os.path.getsize(vpk) / 1024 / 1024:.1f} MB")


if __name__ == "__main__":
    main()
