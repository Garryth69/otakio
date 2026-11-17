"""Health history (tools/probe_sources.merge_health): a worse result needs two checks in a row, a better one counts at once.
python tools/tests/test_health_merge.py"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from probe_sources import merge_health, prune_health, issue_of

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

# entries of extensions that left the catalog are dropped, the others kept as they are
n = prune_health(h, {"a", "b", "c"})
assert n == 2 and sorted(h) == ["a", "b", "c"], h

# where a source stops, in the order the app goes through
assert issue_of({"status": "ok", "popular": 5, "chapters": 3, "pages": 9}) is None
assert issue_of({"status": "dead", "cloudflare": True}) == "blocked"
assert issue_of({"status": "dead", "popular": 0}) == "list"
assert issue_of({"status": "partial", "popular": 20, "chapters": 0}) == "chapters"
assert issue_of({"status": "partial", "popular": 20, "chapters": 9, "pages": 0}) == "pages"
assert issue_of({"status": "partial", "popular": 20, "chapters": 9, "pages": 4, "image": "bad"}) == "images"
print("health merge: OK")
