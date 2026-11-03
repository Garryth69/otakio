"""Compiles every Lua file of the project with LuaJIT (syntax check only)."""
import os, sys
from lupa import luajit21
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L = luajit21.LuaRuntime()
check = L.eval("function(src, name) local f, err = loadstring(src, '@' .. name); return err end")
bad = 0
count = 0
for base in ["source", "repo"]:
    for dp, _, files in os.walk(os.path.join(root, base)):
        for f in files:
            if f.endswith(".lua"):
                p = os.path.join(dp, f)
                count += 1
                err = check(open(p, "rb").read(), os.path.relpath(p, root))
                if err:
                    bad += 1
                    print(err)
print(f"{count} files, {bad} with errors")
sys.exit(1 if bad else 0)
