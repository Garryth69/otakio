"""main.lua replaces the System table with a reduced one (getLanguage, extractZipAsync...) once the libraries are
loaded, so extensions don't get the file system. A library that calls System.<name> later, from inside a function,
gets nil: the reader's "next chapter ahead" and "keep the screen on" failed that way.

Every System.<name> in source/assets/libs and main.lua must be either one the reduced table keeps, or read at load
time: a line with no indentation (`local x = System.x`, top-level code) or one marked `-- load time`."""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2] / "source"
main = (ROOT / "main.lua").read_text(encoding="utf-8")
block = re.search(r"^System = \{(.*?)^\}", main, re.S | re.M)
assert block, "main.lua: the System = { ... } sandbox table was not found"
kept = set(re.findall(r"^\s*(\w+)\s*=", block.group(1), re.M))

bad = []
files = sorted((ROOT / "assets" / "libs").glob("*.lua")) + [ROOT / "main.lua"]
for path in files:
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        code = line.split("--", 1)[0] if "-- load time" not in line else ""
        for name in re.findall(r"\bSystem\.(\w+)", code):
            if name in kept or not line[:1].isspace():
                continue
            bad.append(f"{path.relative_to(ROOT)}:{n}: System.{name} read at run time (keep it in a local at load time)")
if bad:
    print("\n".join(bad))
    sys.exit(1)
print(f"system sandbox: OK ({len(files)} files, kept: {', '.join(sorted(kept))})")
