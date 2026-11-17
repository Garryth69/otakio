"""Domain move detection (tools/probe_sources.find_move / detect_moves), offline: local servers stand for a site that
moved (HTTP redirect, meta refresh), one that sends visitors to a parking page, and one that stays.
python tools/tests/test_domain_move.py"""
import http.server, json, os, sys, tempfile, threading
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import probe_sources as ps


def serve(handler):
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv.server_address[1]


class NewHome(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"<html><title>New home</title></html>")

    def log_message(self, *a):
        pass


new_port = serve(NewHome)
NEW = "http://localhost:%d" % new_port  # another host name than 127.0.0.1: another domain for the detector


class Old(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        mode = self.server.mode
        if mode == "redirect":
            self.send_response(301)
            self.send_header("Location", NEW + "/")
            self.end_headers()
            return
        self.send_response(200)
        self.end_headers()
        body = {"meta": '<meta http-equiv="refresh" content="0;url=%s/">' % NEW,
                "parked": '<meta http-equiv="refresh" content="0;url=http://localhost:%d/lander">' % new_port,
                "stays": "<html>still here</html>"}[mode]
        self.wfile.write(body.encode())

    def log_message(self, *a):
        pass


def old_site(mode):
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Old)
    srv.mode = mode
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return "http://127.0.0.1:%d" % srv.server_address[1]


assert ps.origin_of("https://Site.example:443/a/b") == "https://site.example"
assert ps.origin_of("http://site.example:8080/x") == "http://site.example:8080"
assert ps.host_key("https://www.site.example/") == "site.example"

assert ps.find_move(old_site("redirect")) == NEW, ps.find_move(old_site("redirect"))
assert ps.find_move(old_site("meta")) == NEW
assert ps.find_move(old_site("parked")) is None
assert ps.find_move(old_site("stays")) is None
assert ps.find_move("http://127.0.0.1:9") is None  # nothing answers

# detect_moves: the extension is probed again at the new address; the better result wins and carries movedTo
old = old_site("redirect")
ext = os.path.join(tempfile.mkdtemp(), "x.lua")
open(ext, "w").write('Engines.Madara {id = "X", name = "X", baseUrl = "%s", lang = "en"}' % old)
seen = {}


def fake_probe(entry):
    seen["file"] = open(entry["file"]).read()
    return entry["id"], {"status": "ok", "popular": 3, "chapters": 2, "pages": 5}


ps.probe_entry = fake_probe
results = {"x": {"status": "dead", "popular": 0}, "y": {"status": "ok", "popular": 9}}
ps.detect_moves([{"id": "x", "baseUrl": old, "file": ext}, {"id": "y", "baseUrl": old, "file": ext}], results, 2, verbose=False)
assert results["x"]["status"] == "ok" and results["x"]["movedTo"] == NEW, results["x"]
assert NEW in seen["file"] and old not in seen["file"], seen
assert "movedTo" not in results["y"], "a source whose list loads is not touched"

# the index entry follows health.json
entry = {"id": "x"}
ps.set_moved(entry, results["x"])
assert entry["movedTo"] == NEW
ps.set_moved(entry, {"status": "ok"})
assert "movedTo" not in entry
print("domain move: OK")
