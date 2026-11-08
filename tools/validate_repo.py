"""Validates the extension repository (repo/ or --repo DIR) before it is published.

  python tools/validate_repo.py [--repo DIR] [--git]

Fails (exit 1) on:
- index.json that doesn't parse or lacks the "extensions" list;
- duplicate ids, or entries missing id/name/lang/version/baseUrl, or with neither "file" nor "url";
- a "file" that doesn't exist, or whose sha256 differs from index.json (hashed with LF line endings, as git stores
  it; --git compares against the committed blob instead of the working copy);
- a .lua file that doesn't compile (compiled with LuaJIT, never run);
- a file with an "-- @id" header that doesn't match its entry.
"""
import argparse, hashlib, json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REQUIRED = ("id", "name", "lang", "version", "baseUrl")
HEADER_ID = re.compile(rb"^--\s*@id\s+(\S+)", re.M)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.path.join(ROOT, "repo"))
    ap.add_argument("--git", action="store_true", help="hash the committed blob (HEAD) instead of the working copy")
    args = ap.parse_args()
    from lupa import luajit21
    L = luajit21.LuaRuntime(unpack_returned_tuples=True)
    compile_lua = L.eval("function(src, name) local f, err = loadstring(src, name) return err end")

    errors = []
    try:
        index = json.load(open(os.path.join(args.repo, "index.json"), encoding="utf-8"))
        entries = index["extensions"]
    except Exception as ex:
        print("index.json:", ex)
        sys.exit(1)

    seen = set()
    files = 0
    for e in entries:
        ext_id = e.get("id", "?")
        for k in REQUIRED:
            if e.get(k) in (None, ""):
                errors.append(f"{ext_id}: missing '{k}'")
        if ext_id in seen:
            errors.append(f"{ext_id}: duplicate id")
        seen.add(ext_id)
        if not e.get("file"):
            if not e.get("url"):
                errors.append(f"{ext_id}: neither 'file' nor 'url'")
            continue
        files += 1
        path = os.path.join(args.repo, e["file"])
        if args.git:
            r = subprocess.run(["git", "-C", args.repo, "show", "HEAD:" + e["file"]], capture_output=True)
            if r.returncode:
                errors.append(f"{ext_id}: {e['file']} is not committed")
                continue
            data = r.stdout
        elif not os.path.isfile(path):
            errors.append(f"{ext_id}: {e['file']} not found")
            continue
        else:
            data = open(path, "rb").read().replace(b"\r\n", b"\n")
        if not e.get("sha256"):
            errors.append(f"{ext_id}: no sha256")
        elif hashlib.sha256(data).hexdigest() != e["sha256"]:
            errors.append(f"{ext_id}: sha256 mismatch for {e['file']}")
        err = compile_lua(data.decode("utf-8", "replace"), "=" + e["file"])
        if err:
            errors.append(f"{ext_id}: does not compile: {err}")
        m = HEADER_ID.search(data[:600])
        if m and m.group(1).decode() != ext_id:
            errors.append(f"{ext_id}: header says @id {m.group(1).decode()}")

    for msg in errors:
        print("ERROR", msg)
    print(f"{len(entries)} entries, {files} files checked, {len(errors)} errors")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
