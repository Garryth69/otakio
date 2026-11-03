"""Runs a Lua test file under LuaJIT (via lupa) with the project root as first arg."""
import sys, os
from lupa import luajit21
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\", "/")
L = luajit21.LuaRuntime(unpack_returned_tuples=True)
f = L.eval("function(path, root) local fn, err = loadfile(path); if not fn then error(err) end; return fn(root) end")
for p in sys.argv[1:]:
    f(p.replace("\\", "/"), root)
