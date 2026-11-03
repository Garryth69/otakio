"""Runs one extension through popular -> chapters -> pages and prints every HTTP request it makes.

  python tools/trace_source.py kei.en.toonily
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lua_engine import Engine, ROOT


def main():
    ext_id = sys.argv[1]
    e = Engine()
    real = e._fetch

    def spy(url, method, body, headers):
        r = real(url, method, body, headers)
        print(f"  {method} {url[:140]}" + (f"  body={body[:90]}" if body else "") + f"  -> {len(r)} bytes  {r[:70]!r}")
        return r

    e.L.globals().PY_FETCH = spy
    parser = e.create(os.path.join(ROOT, "repo", "extensions", ext_id + ".lua"), {})
    print(e.check(parser))


if __name__ == "__main__":
    main()
