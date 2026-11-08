"""Checks every interface translation against English: missing keys and mismatched format placeholders.

  python tools/check_lang.py            # exit code 1 when a placeholder differs (missing keys are warnings:
                                        # language.lua falls back to English for them)
"""
import os, re, sys
from lupa import luajit21

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIBS = os.path.join(ROOT, "source", "assets", "libs")
PLACEHOLDER = re.compile(r"%[-+ #0]*\d*(?:\.\d+)?[dsifxXq%]")


def load_all():
    L = luajit21.LuaRuntime(unpack_returned_tuples=True)
    L.execute("Language = {}; LanguageNames = {}")
    names = []
    for f in sorted(os.listdir(LIBS)):
        if f.startswith("lang_") and f.endswith(".lua"):
            L.execute(open(os.path.join(LIBS, f), encoding="utf-8").read())
            names.append(f)
    return L, names


def flatten(L, t, prefix=""):
    out = {}
    for k, v in t.items():
        key = prefix + str(k)
        if L.eval("type")(v) == "table":
            out.update(flatten(L, v, key + "."))
        elif isinstance(v, str):
            out[key] = v
    return out


def main():
    L, files = load_all()
    langs = {k: flatten(L, v) for k, v in L.globals().Language.items() if L.eval("type")(v) == "table"}
    en = langs.pop("English")
    errors = 0
    for name, table in sorted(langs.items()):
        missing = [k for k in en if k not in table]
        bad = [k for k in en if k in table and sorted(PLACEHOLDER.findall(en[k])) != sorted(PLACEHOLDER.findall(table[k]))]
        print("%-20s %4d keys  %3d missing  %d placeholder mismatches" % (name, len(table), len(missing), len(bad)))
        for k in missing[:10]:
            print("   missing:", k)
        for k in bad:
            print("   placeholders differ:", k, repr(en[k]), "->", repr(table[k]))
        errors += len(bad)
    print("%d language files checked" % len(files))
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
