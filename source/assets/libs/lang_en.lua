---English (reference language: every other language falls back to it for missing keys)
Language.English = {
	APP = {LIBRARY = "LIBRARY", CATALOGS = "BROWSE", SETTINGS = "SETTINGS", DOWNLOAD = "DOWNLOADS", HISTORY = "HISTORY", IMPORT = "IMPORT", SEARCH = "Search"},
	DETAILS = {
		ADD_TO_LIBRARY = "Add to library", REMOVE_FROM_LIBRARY = "Remove from library", CONTINUE = "Continue", START = "Start reading",
		DONE = "Completed!", EXPAND = "Read more", SHRINK = "Show less", PAGE = "Page: ", SUMMARY = "Summary"
	},
	EXTRA = {DownloadAll = "Download all chapters", RemoveAll = "Remove downloaded chapters", CancelAll = "Cancel downloads"},
	IMPORT = {DRIVE = "Drive", EXTERNAL_MEMORY = "External memory", FILE = "File", FOLDER = "Folder", GOBACK = "Go back", UNSUPFILE = "Unsupported file"},
	MESSAGE = {
		LOST_CONNECTION = "Connection lost\n\nWaiting for the network…\n\n(Minimize the app, open Wi-Fi settings and press Connect)\n\nPress X to cancel all downloads and close this message.\nDownloads resume when the network comes back.",
		NO_CATALOG_MANGA = "Nothing found.\nThe site, the connection or the source failed.",
		NO_DOWNLOADING_MANGA = "No downloads"
	},
	MODES = {Popular = "Popular", Latest = "Latest", Alphabet = "Alphabetical", ByLetter = "By letter", ByTag = "By genre", Search = "Search"},
	NOTIFICATIONS = {
		ADDED_TO_LIBRARY = "Added to library", REMOVED_FROM_LIBRARY = "Removed from library", BAD_IMAGE_FOUND = "Broken image found",
		CACHE_CLEARED = "Cache cleared", CHAPTERS_CLEARED = "All downloaded chapters were deleted", CHAPTER_REMOVE = "%s deleted",
		COVER_SET_COMPLETED = "Cover updated", IMPORT_COMPLETED = "Import completed", LIBRARY_CLEARED = "Library cleared",
		NET_PROBLEM = "Connection problem", NO_SPACE_LEFT = "Not enough free space", REFRESH_COMPLETED = "Refresh completed",
		SEARCHING = "Searching \"%s\"", SETTINGS_RESET = "Settings reset",
		START_DOWNLOAD = "%s: %s\ndownload started", END_DOWNLOAD = "%s: %s\ndownloaded", CANCEL_DOWNLOAD = "%s: %s\ndownload canceled"
	},
	NSFW = {[true] = "Show", [false] = "Hide"},
	YORN = {[true] = "Yes", [false] = "No"},
	PAGINGCONTROLS = {DPAD = "D-pad", LR = "L and R buttons"},
	PANEL = {
		BACK = "Back", CANCEL = "Cancel", CHANGE_SECTION = "Section", DELETE = "Delete", IMPORT = "Import", MODE = "Mode",
		READ = "Read", SEARCH = "Search", SELECT = "Select", UPDATE = "Refresh"
	},
	PARSERS = {
		DIF = "All languages", ENG = "English", BRA = "Portuguese (Brazil)", PRT = "Portuguese", ESP = "Spanish", FRA = "French",
		DEU = "German", ITA = "Italian", RUS = "Russian", JAP = "Japanese", KOR = "Korean", CHN = "Chinese", IDN = "Indonesian",
		POL = "Polish", ROU = "Romanian", TUR = "Turkish", VIE = "Vietnamese", RAW = "Raw (untranslated)", ARA = "Arabic",
		BUL = "Bulgarian", CES = "Czech", FAS = "Persian", FIL = "Filipino", HIN = "Hindi", HUN = "Hungarian", MSA = "Malay",
		MYA = "Burmese", NLD = "Dutch", THA = "Thai", UKR = "Ukrainian"
	},
	READER = {
		Horizontal = "Horizontal", Vertical = "Vertical", Smart = "Smart", Height = "Fit height", Width = "Fit width", Default = "Default",
		LEFT = "Right to left", RIGHT = "Left to right", DOWN = "Top to bottom",
		LOADING_PAGE = "Loading page", LOADING_SEGMENT = "Loading segment", PREPARING_PAGES = "Preparing pages"
	},
	SETTINGS = {
		SourceLanguages = "Active languages",
		MainSettingsMenu = "More", Language = "Language", ChangeUI = "Theme", Library = "Library", Catalogs = "Browse",
		ExtensionsSettings = "Extensions", Reader = "Reader", Network = "Network", Data = "Data", Other = "Other",
		Controls = "Controls", About = "About",
		LibrarySorting = "Library sorting", LibraryFilter = "Library filter", EditCategories = "Categories",
		RefreshLibAtStart = "Refresh library at startup", AutoDownloadNew = "Download new chapters automatically",
		ShowNSFW = "Show adult (18+) sources", HideInOffline = "Offline: show only downloaded chapters", PreferredCatalogLanguage = "Source language",
		ExtensionRepos = "Repositories", CheckExtUpdatesAtStart = "Check extension updates at startup",
		AutoUpdateExtensions = "Update extensions automatically", ImportNoboruParsers = "Import classic Lua parsers",
		ReaderOrientation = "Reader orientation", ZoomReader = "Page scaling", ReaderDirection = "Reading direction",
		DoubleTapReader = "Double tap to zoom", PressEdgesToChangePage = "Tap page edges to turn pages", PreloadPages = "Pages to preload",
		Incognito = "Incognito mode", SaveImageFormat = "Image save format", ConnectionTime = "Connection timeout (seconds)", ImageProxy = "Image conversion (wsrv.nl)",
		DataSaver = "Data saver", Proxy = "Proxy", UseProxy = "Use proxy", UseProxyAuth = "Proxy authentication", ProxyAuth = "Login:password",
		CreateBackup = "Create backup", RestoreBackup = "Restore backup", ImportNoboruData = "Import from NOBORU",
		SaveDataPath = "Storage for downloads", ClearLibrary = "Clear library", ClearCache = "Clear cache (manga outside the library)",
		ClearAllCache = "Clear all cache", ClearChapters = "Delete all downloaded chapters", ResetAllSettings = "Reset all settings",
		SkipFontLoading = "Skip font preloading", ChapterSorting = "Chapter order", SilentDownloads = "Hide download notifications",
		SkipCacheChapterChecking = "Skip cache check at startup", LoadSummary = "Show manga summary", ShowFPS = "Show FPS counter",
		ShowVersion = "Version", CheckAppUpdate = "Check for app updates", SwapXO = "Confirm button", ChangingPageButtons = "Page turn buttons",
		LeftStickDeadZone = "Left stick dead zone", LeftStickSensitivity = "Left stick sensitivity",
		RightStickDeadZone = "Right stick dead zone", RightStickSensitivity = "Right stick sensitivity",
		EU = "X (Western)", JP = "O (Japanese)", InputValue = "Enter a value", NoConnection = "No connection",
		PressAgainToAccept = "Press again to confirm", ResetCover = "Reset cover", SetPageAsCover = "Use page as cover",
		DownloadImageToMemory = "Save image"
	},
	SETTINGS_DESCRIPTION = {
		Library = "Sorting, filters, categories, updates", Catalogs = "Language, adult content",
		ExtensionsSettings = "Repositories, automatic updates", Reader = "Direction, orientation, zoom",
		Network = "Timeout, image conversion, proxy", Data = "Backup, cache, storage", Other = "Fonts, chapter order, notifications",
		Controls = "Buttons and analog sticks", About = "Version and credits",
		AutoDownloadNew = "After a library refresh", PreloadPages = "Next pages download in the background",
		Incognito = "Doesn't save history or progress", SaveImageFormat = "For “Save image” in the reader", ImageProxy = "Only for formats the Vita can't open (AVIF, JXL, GIF)",
		DataSaver = "Smaller images through the proxy (960px)", ImportNoboruData = "Library, progress and parsers"
	},
	THEME = {Otakio = "Otakio (dark purple)", AMOLED = "AMOLED black", Dark = "Dark", Ocean = "Ocean", Matcha = "Matcha", Crimson = "Crimson", Sakura = "Sakura (light)", Light = "Light"},
	WARNINGS = {NO_CHAPTERS = "No chapters"},
	OTAKIO = {
		REPO_UNOFFICIAL_Q = "Add a third-party repository?", REPO_UNOFFICIAL_MSG = "Extensions are code that runs in the app.\nOnly add repositories you trust.",
		SETUP_INSTALL_RECOMMENDED = "Install recommended sources", SETUP_INSTALL_RECOMMENDED_SUB = "Adds the Garryth69/otakio-extensions repository", RECOMMENDED_QUEUED = "Installing %d recommended sources", RECOMMENDED_NONE = "No recommended sources found (check the connection)",
		REMOVED_FROM_REPO = "Removed from repository · still works, you can uninstall it",
		SETUP_STEP = "Setup %d/%d", SETUP_LANG_HINT = "Language of the menus and buttons.", SETUP_EXTLANG_HINT = "Only these languages appear in Extensions and Browse.\nNone ticked = every language.", SETUP_NSFW_HINT = "Adult sources stay hidden unless you allow them.", SETUP_DIRECTION_HINT = "Manga: right to left. Comics: left to right.\nWebtoons: top to bottom.", SETUP_ORIENTATION_HINT = "How you hold the Vita while reading.", SETUP_KEYS_HINT = "Button that confirms (the other one goes back).", SETUP_DONE_TITLE = "All set!", SETUP_DONE = "Now install your sources in Extensions.\nYou can change everything later in More.", SETUP_OPEN_EXTENSIONS = "Open Extensions", SETUP_FINISH = "Done",
		NAV = {LIBRARY = "Library", UPDATES = "Updates", HISTORY = "History", BROWSE = "Browse", EXTENSIONS = "Extensions", DOWNLOADS = "Downloads", IMPORT = "Import", MORE = "More"},
		LIBRARY = "Library", UPDATES = "Updates", HISTORY = "History", BROWSE = "Browse", EXTENSIONS = "Extensions",
		DOWNLOADS = "Downloads", IMPORT = "Import", MORE = "More", GLOBAL_SEARCH = "Global search",
		ALL = "All", AUTHOR = "Author", ARTIST = "Artist", STATUS = "Status", GENRES = "Genres", N_CHAPTERS = "%d ch.",
		JUST_NOW = "just now", MINUTES_AGO = "%d min ago", HOURS_AGO = "%d h ago", DAYS_AGO = "%d d ago", TODAY = "Today", YESTERDAY = "Yesterday",
		YES = "Yes", NO = "No", OFF = "Off",
		HINT_TOGGLE_APPLY = "X toggle   O / △ apply", HINT_SELECT_BACK = "X select   O back",
		STATUS_OK = "Works", STATUS_UNSTABLE = "Unstable", STATUS_BROKEN = "Doesn't work",
		-- library
		LIBRARY_EMPTY = "Your library is empty", LIBRARY_EMPTY_HINT = "Find something in Browse and press Start\nto add it to your library.",
		LIBRARY_FILTER_EMPTY = "Nothing matches this filter", LIBRARY_FILTER_EMPTY_HINT = "Press Start to change sorting/filter or Square to switch category.",
		LIBRARY_OPTIONS = "Library options", SORT_BY = "Sort by", FILTER = "Filter",
		SORT_NAMES = {["Date added"] = "Date added", ["A-Z"] = "A → Z", ["Z-A"] = "Z → A", Unread = "Unread count", ["Last read"] = "Last read", ["Latest chapter"] = "Latest chapter"},
		FILTER_NAMES = {All = "All", Unread = "Unread", Downloaded = "Downloaded", Completed = "Finished"},
		EDIT_CATEGORIES = "Edit categories", SET_CATEGORIES = "Set categories", N_CATEGORIES = "%d categories", ADD_CATEGORY = "Add category",
		CATEGORY_NAME = "Category name", RENAME = "Rename", MOVE_UP = "Move up", MOVE_DOWN = "Move down", DELETE = "Delete",
		DELETE_CATEGORY_Q = "Delete this category?", REFRESH_LIBRARY = "Refresh library", REFRESHING = "Updating %d/%d",
		CATEGORY = "Category", OPTIONS = "Options", CONTINUE_READING = "Continue", IN_LIBRARY = "In library", ADD_REMOVE = "Library +/-",
		NEW_CHAPTERS_FOUND = "%d new chapters!",
		-- browse
		NO_SOURCES = "No sources installed", NO_SOURCES_HINT = "Open the Extensions tab (R) and pick the sources you want.",
		NO_SOURCES_LANG = "No sources for this language", NO_SOURCES_LANG_HINT = "Press Start to change the language filter.",
		PIN = "Pin", UNPIN = "Unpin", LANGUAGE = "Language", NEW = "NEW",
		NO_RESULTS = "No results", SEARCHING_N = "Searching %d/%d", OPEN_IN_SOURCE = "Open in source",
		NO_SOURCE_SEARCH = "This source has no search",
		-- updates / history
		NO_UPDATES = "No recent updates", NO_UPDATES_HINT = "Press Start (or △ in Library) to look for new chapters.",
		CLEAR_UPDATES_Q = "Clear the updates list?", MANGA_NOT_FOUND = "Manga not found in library", ALREADY_DOWNLOADED = "Already downloaded",
		NO_HISTORY = "Nothing read recently", NO_HISTORY_HINT = "Chapters you read show up here.",
		RESUME = "Resume", START = "Start", INCOGNITO_ON = "Incognito mode is on", DETAILS = "Details", DOWNLOAD = "Download", CLEAR = "Clear",
		-- downloads
		DOWNLOADS_HINT = "Use Square on a chapter or Start on a manga page to download.", PREPARING = "preparing…", QUEUED = "queued",
		QUEUED_N = "%d chapters queued", CANCEL_ALL = "Cancel all", DOWNLOADED_N = "Downloaded (%d)",
		MARK_ALL_READ = "Mark all as read", MARK_ALL_UNREAD = "Mark all as unread", MARK_PREVIOUS_READ = "Mark previous as read",
		DOWNLOAD_NEXT_5 = "Download next 5 unread", DOWNLOAD_UNREAD = "Download all unread",
		-- extensions
		INSTALLED = "Installed", AVAILABLE = "Available", UPDATES_TAB = "Updates", INSTALL = "Install", UPDATE = "Update", INSTALLED_LABEL = "Installed",
		UNINSTALL = "Uninstall", UNINSTALL_Q = "Uninstall %s?", OPEN_SOURCE = "Open source", SOURCE_HIDDEN = "Source unavailable (adult content is off or the extension failed to load)",
		EXT_INSTALLED = "%s installed", EXT_UPDATED = "%s updated", EXT_UNINSTALLED = "%s uninstalled", EXT_INSTALL_FAILED = "Couldn't install %s",
		EXT_UPDATES_AVAILABLE = "Extension updates available: %d", NO_EXTENSIONS = "No extensions installed", NO_PAGES = "This chapter has no pages yet", ERROR_RECOVERED = "Something went wrong, back to the Library (details in log.txt)", NO_REPOS = "No extension repository", NO_REPOS_HINT = "Otakio has no built-in sources. Select > Add repository.", APP_UP_TO_DATE = "Otakio is up to date", APP_UPDATE_AVAILABLE = "Otakio %s is available", APP_UPDATE_Q = "Download Otakio %s?", APP_UPDATE_HINT = "The VPK goes to ux0:/vpk/. Install it with VitaShell; your library and settings are kept.", APP_UPDATE_DOWNLOADING = "Downloading Otakio %s...", APP_UPDATE_DONE = "Saved to %s. Install it with VitaShell.", APP_UPDATE_FAILED = "Could not check for updates", CHECKING = "Checking...",
		NO_EXTENSIONS_HINT = "Square switches to the Available tab.", ALL_UP_TO_DATE = "Everything is up to date",
		NOTHING_HERE = "Nothing here", CHANGE_FILTERS_HINT = "Try another language (Start) or search (△).",
		SEARCH_EXTENSIONS = "Search extensions", ALL_LANGUAGES = "All languages", TAB = "Tab", REPOSITORIES = "Repositories",
		REFRESH_REPOS = "Refresh repositories", UPDATE_ALL = "Update all", ADD_REPO = "Add repository", REPO_URL = "GitHub user/repo or index.json URL",
		REPO_EXISTS = "Repository already added", REMOVE_REPO_Q = "Remove %s?", REPO_BUILTIN = "Built-in · online", REPO_OFFLINE = "Built-in · offline copy",
		REPO_MIHON = "Mihon repo · %d of %d sources work in Otakio", REPO_NEEDS_UPDATE = "%s needs a newer Otakio", N_REPOS = "%d repositories",
		LANG_EN = "English", LANG_PT = "Portuguese", LANG_ES = "Spanish", LANG_FR = "French", LANG_DE = "German", LANG_IT = "Italian",
		LANG_RU = "Russian", LANG_JA = "Japanese", LANG_ZH = "Chinese",
		LANG_MULTI = "Multi-language", LANG_OTHER = "Other",
		PROTECTED_CHAPTER = "This chapter is protected by the site and isn't supported yet",
		-- import
		IMPORT_EMPTY = "Nothing to import yet",
		IMPORT_HELP = "Copy to the folder above (VitaShell FTP or USB):\n• a .cbz or .zip file\n• a folder with the page images\n• a manga folder with one chapter per folder or .cbz\nThen X reads it and Square adds it to the Library.",
		IMPORTED_N = "%d items imported",
		-- settings / data
		PROXY_MODES = {Auto = "Only when needed", Off = "Off"}, PROXY_ADDRESS = "Address (IP:port)",
		BACKUP_CREATED = "Backup saved:\n%s", BACKUP_FAILED = "Couldn't create backup", BACKUP_INVALID = "Invalid backup file",
		BACKUP_RESTORED = "Backup restored (%d new manga)", NO_BACKUPS = "No backups in ux0:data/otakio/backups",
		RESTORE_BACKUP = "Restore backup", RESTORE_BACKUP_Q = "Restore this backup?",
		IMPORT_NOBORU_Q = "Import from NOBORU?", IMPORT_NOBORU_DESC = "Library, reading progress and parsers will be copied.\nDownloaded chapters stay in their original folder.",
		IMPORT_NOBORU_PARSERS = "Import classic Lua parsers", NOBORU_IMPORTED = "Imported %d manga and %d parsers",
		NOBORU_NOT_FOUND = "No NOBORU data found (ux0:data/noboru)",
		-- about
		ABOUT_TAGLINE = "Manga and comics reader for PS Vita",
		CREDITS_AUTHOR = "Author", CREDITS_AI = "developed with AI assistance (Claude, Anthropic)", CREDITS_BASED_ON = "Based on", CREDITS_ENGINE = "Engine", CREDITS_SOURCES = "Sources",
		CREDITS_SOURCES_TEXT = "Themes and extensions adapted from the keiyoushi (Mihon) project",
		CREDITS_TRANSLATIONS = "Translations", CREDITS_REVISED = "revised for Otakio",
		CREDITS_SUPPORT = "Support the authors: buy the official releases."
	}
}
