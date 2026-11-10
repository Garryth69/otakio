"""Health history (tools/probe_sources.merge_health): a worse result needs two checks in a row, a better one counts at once.
python tools/tests/test_health_merge.py"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from probe_sources import merge_health

h = {"a": {"status": "ok"}, "b": {"status": "ok"}, "c": {"status": "dead", "deadSince": "2026-11-01"}, "d": {"status": "ok"}}
merge_health(h, {"a": {"status": "dead", "error": "timeout"}, "b": {"status": "dead"}, "c": {"status": "ok"},
                 "d": {"status": "partial"}}, today="2026-11-10")
assert h["a"]["status"] == "ok" and h["a"]["pending"] == {"status": "dead", "since": "2026-11-10", "error": "timeout"}, h["a"]
assert h["c"]["status"] == "ok" and "deadSince" not in h["c"], h["c"]
assert h["d"]["status"] == "ok" and h["d"]["pending"]["status"] == "partial", h["d"]

merge_health(h, {"a": {"status": "dead"}, "b": {"status": "ok"}, "d": {"status": "partial"}}, today="2026-11-11")
assert h["a"]["status"] == "dead" and h["a"]["deadSince"] == "2026-11-10" and "pending" not in h["a"], h["a"]
assert h["b"]["status"] == "ok" and "pending" not in h["b"], h["b"]
assert h["d"]["status"] == "partial" and "pending" not in h["d"], h["d"]

# a dead run goes on with its first date; a new source is taken as it is
merge_health(h, {"a": {"status": "dead"}, "e": {"status": "dead"}}, today="2026-11-12")
assert h["a"]["deadSince"] == "2026-11-10", h["a"]
assert h["e"]["status"] == "dead" and h["e"]["deadSince"] == "2026-11-12", h["e"]
print("health merge: OK")
