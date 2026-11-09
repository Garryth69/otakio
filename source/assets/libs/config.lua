---Otakio global configuration
Config = {
	APP_NAME = "Otakio",
	VERSION = 1.1,
	VERSION_NAME = "1.1.2",
	TITLE_ID = "OTAK00001",
	-- helper title that installs updates while Otakio is closed (source/updater/)
	UPDATER_TITLE_ID = "OTAK00002",
	DATA = "ux0:data/otakio/",
	-- Engine API level exposed to extensions (index.json "minEngine")
	ENGINE_LEVEL = 1,
	-- The app ships without extensions. Sources come from extension repositories the user adds
	-- (Extensions > Select > Add repository). Test builds may bundle a catalog in app0:repo/.
	OFFICIAL_REPO_URL = "",
	-- Extension repository the first-run setup offers to add (only when the user picks "Install recommended sources")
	EXTENSIONS_REPO = "Garryth69/otakio-extensions",
	BUILTIN_REPO = "app0:repo/",
	-- App updates: latest GitHub release of this repository (its .vpk asset)
	GITHUB_REPO = "Garryth69/otakio",
	-- Image proxy used to convert formats the Vita can't decode (WebP/AVIF) and to downscale huge pages
	IMAGE_PROXY = "https://wsrv.nl/?url=%s&output=jpg&q=85&we",
	-- Layout
	RAIL_WIDTH = 84,
	SCREEN_W = 960,
	SCREEN_H = 544
}
