# Adds System.convertImage to lpp-vita's luaSystem.cpp (run inside lpp-vita/source)
p = "luaSystem.cpp"
s = open(p).read()
if "lua_convertimage" not in s:
    s = s.replace("static const luaL_Reg System_functions[] = {", '''extern "C" int otakio_convert_image(const char *src, const char *dst, int to, int quality);

// Otakio: System.convertImage(src, dst, "jpg"|"png"|"webp"[, quality]) -> boolean (JPEG/PNG/WebP in, full resolution)
static int lua_convertimage(lua_State *L){
	const char *src = luaL_checkstring(L, 1);
	const char *dst = luaL_checkstring(L, 2);
	const char *fmt = luaL_optstring(L, 3, "jpg");
	int quality = luaL_optinteger(L, 4, 92);
	int to = strcmp(fmt, "png") == 0 ? 1 : strcmp(fmt, "webp") == 0 ? 2 : 0;
	lua_pushboolean(L, otakio_convert_image(src, dst, to, quality));
	return 1;
}

static const luaL_Reg System_functions[] = {''', 1)
    s = s.replace('  {"takeScreenshot",            lua_screenshot},', '  {"takeScreenshot",            lua_screenshot},\n  {"convertImage",              lua_convertimage},', 1)
    open(p, "w").write(s)
print("convertImage" in s)
