"""Reads a Vita crash dump (ux0:data/psp2core-*.psp2dmp) against the engine's ELF with symbols.

    python tools/parse_crash.py <dump.psp2dmp> <lpp-vita.elf.unstripped.elf> [--parser DIR]

DIR is a checkout of https://github.com/xyzz/vita-parse-core (default: ../_ref/vita-parse-core). Needs pyelftools and
the VitaSDK binutils (arm-vita-eabi-objdump/addr2line) on PATH. The dump is gzip-compressed; it is unpacked to a
temporary file. vita-parse-core still has a few Python 2 leftovers: they are patched in a temporary copy.
"""
import argparse
import gzip
import os
import shutil
import subprocess
import sys
import tempfile

PY3_SHIM = '''def str2bytes(s):
    return s.encode("latin-1") if isinstance(s, str) else s
def bytes2str(b):
    return b.decode("latin-1") if isinstance(b, bytes) else b
'''

C_STR = '''def c_str(buf, off):
    end = buf.find(b"\\0", off) if isinstance(buf, bytes) else buf.find("\\0", off)
    out = buf[off:end if end >= 0 else len(buf)]
    return out.decode("latin-1") if isinstance(out, bytes) else out
'''


def patched_copy(src, dst):
    shutil.copytree(src, dst, ignore=shutil.ignore_patterns(".git"))
    for name in ("util.py", "elf.py"):
        path = os.path.join(dst, name)
        with open(path, encoding="utf-8") as f:
            text = f.read()
        text = text.replace("from elftools.common.py3compat import str2bytes, bytes2str", PY3_SHIM)
        text = text.replace("from elftools.common.py3compat import str2bytes", PY3_SHIM)
        text = text.replace("xrange(", "range(").replace("string.letters", "string.ascii_letters")
        if name == "util.py":
            start = text.find("def c_str(")
            end = text.find("\ndef ", start + 1)
            if start >= 0:
                text = text[:start] + C_STR + text[end:]
            text = text.replace('"%02x" % ord(x)', '"%02x" % (x if isinstance(x, int) else ord(x))')
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dump")
    ap.add_argument("elf")
    ap.add_argument("--parser", default=os.path.join(here, "..", "_ref", "vita-parse-core"))
    args = ap.parse_args()
    if not os.path.isfile(os.path.join(args.parser, "main.py")):
        sys.exit("vita-parse-core not found at %s (use --parser)" % args.parser)
    with tempfile.TemporaryDirectory() as tmp:
        core = os.path.join(tmp, "core.elf")
        with open(args.dump, "rb") as f:
            data = f.read()
        if data[:2] == b"\x1f\x8b":
            data = gzip.decompress(data)
        with open(core, "wb") as f:
            f.write(data)
        parser = os.path.join(tmp, "parser")
        patched_copy(args.parser, parser)
        return subprocess.call([sys.executable, os.path.join(parser, "main.py"), core, args.elf])


if __name__ == "__main__":
    sys.exit(main())
