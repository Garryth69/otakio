---Русский (based on Creckeryop's Russian translation of NOBORU, revised for Otakio)
Language.Russian = {
	APP = {LIBRARY = "БИБЛИОТЕКА", CATALOGS = "КАТАЛОГ", SETTINGS = "НАСТРОЙКИ", DOWNLOAD = "ЗАГРУЗКИ", HISTORY = "ИСТОРИЯ", IMPORT = "ИМПОРТ", SEARCH = "Поиск"},
	DETAILS = {
		ADD_TO_LIBRARY = "В библиотеку", REMOVE_FROM_LIBRARY = "Убрать из библиотеки", CONTINUE = "Продолжить", START = "Начать читать",
		DONE = "Прочитано!", EXPAND = "Подробнее", SHRINK = "Свернуть", PAGE = "Страница: ", SUMMARY = "Описание"
	},
	EXTRA = {DownloadAll = "Скачать все главы", RemoveAll = "Удалить скачанные главы", CancelAll = "Отменить загрузки"},
	IMPORT = {DRIVE = "Диск", EXTERNAL_MEMORY = "Внешняя память", FILE = "Файл", FOLDER = "Папка", GOBACK = "Назад", UNSUPFILE = "Неподдерживаемый файл"},
	MESSAGE = {
		LOST_CONNECTION = "Соединение потеряно\n\nОжидание сети…\n\n(Сверните приложение, откройте настройки Wi-Fi и нажмите «Подключиться»)\n\nНажмите ✕, чтобы отменить все загрузки и закрыть это сообщение.\nЗагрузки продолжатся, когда сеть вернётся.",
		NO_CATALOG_MANGA = "Ничего не найдено.\nОшибка сайта, соединения или источника.",
		NO_DOWNLOADING_MANGA = "Нет загрузок"
	},
	MODES = {Popular = "Популярное", Latest = "Новое", Alphabet = "По алфавиту", ByLetter = "По букве", ByTag = "По жанру", Search = "Поиск"},
	NOTIFICATIONS = {
		ADDED_TO_LIBRARY = "Добавлено в библиотеку", REMOVED_FROM_LIBRARY = "Удалено из библиотеки", BAD_IMAGE_FOUND = "Найдено повреждённое изображение",
		CACHE_CLEARED = "Кэш очищен", CHAPTERS_CLEARED = "Все скачанные главы удалены", CHAPTER_REMOVE = "%s удалено",
		COVER_SET_COMPLETED = "Обложка обновлена", IMPORT_COMPLETED = "Импорт завершён", LIBRARY_CLEARED = "Библиотека очищена",
		NET_PROBLEM = "Проблема с соединением", NO_SPACE_LEFT = "Недостаточно свободного места", REFRESH_COMPLETED = "Обновление завершено",
		SEARCHING = "Поиск «%s»", SETTINGS_RESET = "Настройки сброшены",
		START_DOWNLOAD = "%s: %s\nзагрузка начата", END_DOWNLOAD = "%s: %s\nскачано", CANCEL_DOWNLOAD = "%s: %s\nзагрузка отменена"
	},
	NSFW = {[true] = "Показывать", [false] = "Скрывать"},
	YORN = {[true] = "Да", [false] = "Нет"},
	PAGINGCONTROLS = {DPAD = "Крестовина", LR = "Кнопки L и R"},
	PANEL = {
		BACK = "Назад", CANCEL = "Отмена", CHANGE_SECTION = "Раздел", DELETE = "Удалить", IMPORT = "Импорт", MODE = "Режим",
		READ = "Читать", SEARCH = "Поиск", SELECT = "Выбрать", UPDATE = "Обновить"
	},
	PARSERS = {
		DIF = "Все языки", ENG = "Английский", BRA = "Португальский (Бразилия)", PRT = "Португальский", ESP = "Испанский", FRA = "Французский",
		DEU = "Немецкий", ITA = "Итальянский", RUS = "Русский", JAP = "Японский", KOR = "Корейский", CHN = "Китайский", IDN = "Индонезийский",
		POL = "Польский", ROU = "Румынский", TUR = "Турецкий", VIE = "Вьетнамский", RAW = "Оригинал (без перевода)", ARA = "Арабский",
		BUL = "Болгарский", CES = "Чешский", FAS = "Персидский", FIL = "Филиппинский", HIN = "Хинди", HUN = "Венгерский", MSA = "Малайский",
		MYA = "Бирманский", NLD = "Нидерландский", THA = "Тайский", UKR = "Украинский"
	},
	READER = {
		Horizontal = "Горизонтально", Vertical = "Вертикально", Smart = "Умный", Height = "По высоте", Width = "По ширине", Default = "По умолчанию",
		LEFT = "Справа налево", RIGHT = "Слева направо", DOWN = "Сверху вниз", WEBTOON = "Вебтун (непрерывно)", WT_NEXT = "Следующая глава: продолжайте листать", WT_PREV = "Предыдущая глава: продолжайте листать", WT_LAST = "Это последняя глава",
		LOADING_PAGE = "Загрузка страницы", LOADING_SEGMENT = "Загрузка фрагмента", PREPARING_PAGES = "Подготовка страниц"
	},
	SETTINGS = {
		SourceLanguages = "Активные языки",
		MainSettingsMenu = "Ещё", Language = "Язык", ChangeUI = "Тема", Library = "Библиотека", Catalogs = "Каталог",
		ExtensionsSettings = "Расширения", Reader = "Читалка", Network = "Сеть", Data = "Данные", Other = "Прочее",
		Controls = "Управление", About = "О программе",
		LibrarySorting = "Сортировка библиотеки", LibraryFilter = "Фильтр библиотеки", EditCategories = "Категории",
		RefreshLibAtStart = "Обновлять библиотеку при запуске", AutoDownloadNew = "Скачивать новые главы автоматически",
		ShowNSFW = "Показывать источники 18+", HideInOffline = "Без сети: только скачанные главы", PreferredCatalogLanguage = "Язык источников",
		ExtensionRepos = "Репозитории", CheckExtUpdatesAtStart = "Проверять обновления расширений при запуске",
		AutoUpdateExtensions = "Обновлять расширения автоматически", ImportNoboruParsers = "Импорт классических Lua-парсеров",
		ReaderOrientation = "Ориентация читалки", ZoomReader = "Масштаб страницы", ReaderDirection = "Направление чтения",
		DoubleTapReader = "Двойное касание для масштаба", PressEdgesToChangePage = "Касание краёв листает страницы", PreloadPages = "Предзагрузка страниц",
		Incognito = "Режим инкогнито", SaveImageFormat = "Формат сохранения изображений", ConnectionTime = "Тайм-аут соединения (секунды)", ImageProxy = "Конвертация изображений (wsrv.nl)",
		DataSaver = "Экономия трафика", Proxy = "Прокси", UseProxy = "Использовать прокси", UseProxyAuth = "Авторизация прокси", ProxyAuth = "Логин:пароль",
		CreateBackup = "Создать резервную копию", RestoreBackup = "Восстановить копию", ImportNoboruData = "Импорт из NOBORU",
		SaveDataPath = "Место для загрузок", ClearLibrary = "Очистить библиотеку", ClearCache = "Очистить кэш (манга вне библиотеки)",
		ClearAllCache = "Очистить весь кэш", ClearChapters = "Удалить все скачанные главы", ResetAllSettings = "Сбросить все настройки",
		SkipFontLoading = "Пропустить предзагрузку шрифтов", ChapterSorting = "Порядок глав", SilentDownloads = "Скрыть уведомления о загрузках",
		SkipCacheChapterChecking = "Пропустить проверку кэша при запуске", LoadSummary = "Показывать описание манги", ShowFPS = "Показывать FPS",
		ShowVersion = "Версия", CheckAppUpdate = "Проверить обновления приложения", AppAutoUpdate = "Проверять обновления при запуске", SwapXO = "Кнопка подтверждения", ChangingPageButtons = "Кнопки перелистывания",
		LeftStickDeadZone = "Мёртвая зона левого стика", LeftStickSensitivity = "Чувствительность левого стика",
		RightStickDeadZone = "Мёртвая зона правого стика", RightStickSensitivity = "Чувствительность правого стика",
		EU = "X (западная)", JP = "O (японская)", InputValue = "Введите значение", NoConnection = "Нет соединения",
		PressAgainToAccept = "Нажмите ещё раз для подтверждения", ResetCover = "Сбросить обложку", SetPageAsCover = "Сделать страницу обложкой",
		DownloadImageToMemory = "Сохранить изображение"
	},
	SETTINGS_DESCRIPTION = {
		Library = "Сортировка, фильтры, категории, обновления", Catalogs = "Язык, контент 18+",
		ExtensionsSettings = "Репозитории, автообновление", Reader = "Направление, ориентация, масштаб",
		Network = "Тайм-аут, конвертация изображений, прокси", Data = "Резервные копии, кэш, хранилище", Other = "Шрифты, порядок глав, уведомления",
		Controls = "Кнопки и стики", About = "Версия и авторы",
		AutoDownloadNew = "После обновления библиотеки", PreloadPages = "Следующие страницы скачиваются в фоне",
		Incognito = "Не сохраняет историю и прогресс", SaveImageFormat = "Для «Сохранить изображение» в читалке. Преобразование в другой формат занимает несколько секунд", ImageProxy = "Только для форматов, которые Vita не открывает (AVIF, JXL, GIF)",
		DataSaver = "Уменьшенные изображения через прокси (960px)", ImportNoboruData = "Библиотека, прогресс и парсеры"
	},
	THEME = {Otakio = "Otakio (тёмно-фиолетовая)", AMOLED = "AMOLED чёрная", Dark = "Тёмная", Ocean = "Океан", Matcha = "Матча", Crimson = "Багровая", Sakura = "Сакура (светлая)", Light = "Светлая"},
	WARNINGS = {NO_CHAPTERS = "Нет глав"},
	OTAKIO = {
		REPO_UNOFFICIAL_Q = "Добавить сторонний репозиторий?", REPO_UNOFFICIAL_MSG = "Расширения — это код, который выполняется в приложении.\nДобавляйте только доверенные репозитории.",
		SETUP_INSTALL_RECOMMENDED = "Установить рекомендуемые источники", SETUP_INSTALL_RECOMMENDED_SUB = "Добавляет репозиторий Garryth69/otakio-extensions", RECOMMENDED_QUEUED = "Устанавливается рекомендуемых источников: %d", RECOMMENDED_NONE = "Не удалось прочитать репозиторий расширений (проверьте соединение). Повторите в Расширения > Репозитории", RECOMMENDED_ALL_INSTALLED = "Рекомендуемые источники уже установлены", RECOMMENDED_NONE_LANG = "Нет рекомендуемых источников для выбранных языков", SAVE_FORMAT_ORIGINAL = "Исходный",
		REMOVED_FROM_REPO = "Удалено из репозитория · пока работает, можно удалить",
		SETUP_STEP = "Настройка %d/%d", SETUP_LANG_HINT = "Язык меню и кнопок.", SETUP_EXTLANG_HINT = "В Плагинах и Обзоре видны только эти языки.\nНичего не выбрано = все языки.", SETUP_NSFW_HINT = "Источники 18+ скрыты, пока вы их не разрешите.", SETUP_DIRECTION_HINT = "Манга: справа налево. Комиксы: слева направо.\nВебтуны: сверху вниз.", SETUP_ORIENTATION_HINT = "Как вы держите Vita во время чтения.", SETUP_KEYS_HINT = "Кнопка подтверждения (другая — назад).", SETUP_DONE_TITLE = "Готово!", SETUP_DONE = "Теперь установите источники в разделе Плагины.\nВсё можно изменить позже в разделе Ещё.", SETUP_FINISH = "Готово",
		NAV = {LIBRARY = "Полка", UPDATES = "Новинки", HISTORY = "История", BROWSE = "Каталог", EXTENSIONS = "Плагины", DOWNLOADS = "Загрузки", IMPORT = "Импорт", MORE = "Ещё"},
		LIBRARY = "Библиотека", UPDATES = "Обновления", HISTORY = "История", BROWSE = "Каталог", EXTENSIONS = "Расширения",
		DOWNLOADS = "Загрузки", IMPORT = "Импорт", MORE = "Ещё", GLOBAL_SEARCH = "Глобальный поиск",
		ALL = "Все", AUTHOR = "Автор", ARTIST = "Художник", STATUS = "Статус", GENRES = "Жанры", N_CHAPTERS = "%d гл.",
		JUST_NOW = "только что", MINUTES_AGO = "%d мин назад", HOURS_AGO = "%d ч назад", DAYS_AGO = "%d д назад", TODAY = "Сегодня", YESTERDAY = "Вчера",
		YES = "Да", NO = "Нет", OFF = "Выкл.",
		HINT_TOGGLE_APPLY = "X переключить   O / △ применить", HINT_SELECT_BACK = "X выбрать   O назад",
		STATUS_OK = "Работает", STATUS_UNSTABLE = "Нестабильно", STATUS_BROKEN = "Не работает",
		-- library
		LIBRARY_EMPTY = "Библиотека пуста", LIBRARY_EMPTY_HINT = "Найдите что-нибудь в Каталоге и нажмите START,\nчтобы добавить в библиотеку.",
		LIBRARY_FILTER_EMPTY = "Ничего не подходит под фильтр", LIBRARY_FILTER_EMPTY_HINT = "START — сортировка/фильтр, □ — сменить категорию.",
		LIBRARY_OPTIONS = "Параметры библиотеки", SORT_BY = "Сортировка", FILTER = "Фильтр",
		SORT_NAMES = {["Date added"] = "Дата добавления", ["A-Z"] = "А → Я", ["Z-A"] = "Я → А", Unread = "Непрочитанные", ["Last read"] = "Последнее чтение", ["Latest chapter"] = "Новая глава"},
		FILTER_NAMES = {All = "Все", Unread = "Непрочитанные", Downloaded = "Скачанные", Completed = "Прочитанные"},
		EDIT_CATEGORIES = "Изменить категории", SET_CATEGORIES = "Назначить категории", N_CATEGORIES = "Категорий: %d", ADD_CATEGORY = "Добавить категорию",
		CATEGORY_NAME = "Название категории", RENAME = "Переименовать", MOVE_UP = "Выше", MOVE_DOWN = "Ниже", DELETE = "Удалить",
		DELETE_CATEGORY_Q = "Удалить эту категорию?", REFRESH_LIBRARY = "Обновить библиотеку", REFRESHING = "Обновление %d/%d",
		CATEGORY = "Категория", OPTIONS = "Параметры", CONTINUE_READING = "Продолжить", IN_LIBRARY = "В библиотеке", ADD_REMOVE = "Библиотека +/-",
		NEW_CHAPTERS_FOUND = "Новых глав: %d!",
		-- browse
		NO_SOURCES = "Источники не установлены", NO_SOURCES_HINT = "Откройте вкладку Расширения (R) и выберите нужные источники.",
		NO_SOURCES_LANG = "Нет источников на этом языке", NO_SOURCES_LANG_HINT = "Нажмите START, чтобы сменить фильтр языка.",
		PIN = "Закрепить", UNPIN = "Открепить", LANGUAGE = "Язык", NEW = "НОВОЕ",
		NO_RESULTS = "Нет результатов", SEARCHING_N = "Поиск %d/%d", OPEN_IN_SOURCE = "Открыть в источнике",
		NO_SOURCE_SEARCH = "В этом источнике нет поиска",
		-- updates / history
		NO_UPDATES = "Нет недавних обновлений", NO_UPDATES_HINT = "Нажмите △, чтобы найти новые главы.",
		CLEAR_UPDATES_Q = "Очистить список обновлений?", MANGA_NOT_FOUND = "Манга не найдена в библиотеке", ALREADY_DOWNLOADED = "Уже скачано",
		NO_HISTORY = "Вы ещё ничего не читали", NO_HISTORY_HINT = "Здесь появятся прочитанные главы.",
		RESUME = "Продолжить", START = "Начать", INCOGNITO_ON = "Включён режим инкогнито", DETAILS = "Подробнее", DOWNLOAD = "Скачать", CLEAR = "Очистить",
		-- downloads
		DOWNLOADS_HINT = "□ на главе или START на странице манги — скачать.", PREPARING = "подготовка…", QUEUED = "в очереди",
		QUEUED_N = "Глав в очереди: %d", CANCEL_ALL = "Отменить все", DOWNLOADED_N = "Скачано (%d)",
		MARK_ALL_READ = "Отметить всё прочитанным", MARK_ALL_UNREAD = "Отметить всё непрочитанным", MARK_PREVIOUS_READ = "Отметить предыдущие прочитанными",
		DOWNLOAD_NEXT_5 = "Скачать следующие 5 непрочитанных", DOWNLOAD_UNREAD = "Скачать все непрочитанные",
		-- extensions
		INSTALLED = "Установленные", AVAILABLE = "Доступные", UPDATES_TAB = "Обновления", INSTALL = "Установить", UPDATE = "Обновить", INSTALLED_LABEL = "Установлено",
		UNINSTALL = "Удалить", UNINSTALL_Q = "Удалить %s?", OPEN_SOURCE = "Открыть источник", SOURCE_HIDDEN = "Источник недоступен (контент 18+ выключен или расширение не загрузилось)",
		EXT_INSTALLED = "%s установлено", EXT_UPDATED = "%s обновлено", EXT_UNINSTALLED = "%s удалено", EXT_INSTALL_FAILED = "Не удалось установить %s",
		EXT_UPDATES_AVAILABLE = "Доступно обновлений расширений: %d", NO_EXTENSIONS = "Расширения не установлены", NO_PAGES = "В этой главе пока нет страниц", ERROR_RECOVERED = "Что-то пошло не так, возврат в Библиотеку (подробности в log.txt)", NO_REPOS = "Нет репозитория расширений", NO_REPOS_HINT = "В Otakio нет встроенных источников. SELECT > Добавить репозиторий.", APP_UP_TO_DATE = "Установлена последняя версия Otakio", APP_UPDATE_AVAILABLE = "Доступен Otakio %s", APP_UPDATE_Q = "Обновить до Otakio %s?", APP_UPDATE_HINT = "Otakio скачает и установит его, затем перезапустится. Библиотека и настройки сохранятся.", APP_UPDATE_DOWNLOADING = "Загрузка Otakio %s...", APP_UPDATE_DONE = "Сохранено в %s. Установите через VitaShell.", APP_UPDATE_FAILED = "Не удалось проверить обновления", APP_UPDATE_RESTARTING = "Otakio закроется, установит %s и откроется снова...", APP_UPDATE_DONE_NOW = "Обновлено до Otakio %s", APP_UPDATE_DL_FAILED = "Не удалось скачать обновление. Попробуйте позже.", APP_UPDATE_INSTALLING = "Установка Otakio %s...", APP_UPDATE_STEP = "Шаг %d из %d", APP_UPDATE_EXTRACTING = "Распаковка обновления...", APP_UPDATE_PREPARING = "Подготовка установщика...", APP_UPDATE_DONT_OFF = "Не выключайте систему", APP_UPDATE_CANCEL = "Отмена", APP_UPDATE_CANCELED = "Обновление отменено", RS_TITLE = "Настройки чтения", RS_THIS_MANGA = "Эта манга", RS_COLORS = "Цвета страниц", RS_READER = "Читалка", RS_PAGE = "Эта страница", RS_BACKGROUND = "Фон", RS_BG_THEME = "Тема", RS_BG_BLACK = "Чёрный", RS_BG_GRAY = "Серый", RS_BG_WHITE = "Белый", RS_BRIGHTNESS = "Яркость", RS_FILTER = "Цветовой фильтр", RS_PRESET = "Шаблон", RS_PRESET_CUSTOM = "Свой", RS_PRESET_SEPIA = "Сепия", RS_PRESET_PAPER = "Бумага", RS_PRESET_WARM = "Тёплый", RS_PRESET_NIGHT = "Ночь", RS_BLEND = "Режим наложения", RS_BLEND_DEFAULT = "Обычный", RS_BLEND_MULTIPLY = "Умножение", RS_RED = "Красный", RS_GREEN = "Зелёный", RS_BLUE = "Синий", RS_OPACITY = "Непрозрачность", RS_PAGE_NUMBER = "Показывать номер страницы", RS_RESET = "Сбросить цвета", RS_ADJUST = "Изменить", RS_CLOSE = "Закрыть", DL_VIEW_QUEUE = "Очередь", DL_VIEW_DONE = "Загружено", DL_VIEW_HISTORY = "История", DL_VIEW = "Вид", DL_QUEUE_EMPTY = "Сейчас ничего не загружается", DL_HISTORY_EMPTY = "История загрузок пуста", DL_HISTORY_HINT = "Здесь отображаются завершённые, неудачные и отменённые загрузки.", DL_CLEAR_HISTORY = "Очистить историю", DL_CLEAR_HISTORY_Q = "Загруженные главы сохранятся.", DL_HISTORY_CLEARED = "История загрузок очищена", DL_STATUS_OK = "Загружено", DL_STATUS_FAILED = "Ошибка", DL_STATUS_CANCELED = "Отменено", DL_REMOVE_ENTRY = "Убрать", DL_CHAPTERS = "Главы", DL_TAP_DELETE = "Удалить эту загрузку", DL_DELETE_CHAPTER = "Удалить эту загруженную главу?", DATA_MIGRATION_FAILED = "Не удалось обновить данные для этой версии: они остались без изменений (подробности в log.txt)", APP_UPDATE_INSTALLED = "Otakio %s установлен. Перезапуск...", APP_UPDATE_NO_SPACE = "Недостаточно свободного места для обновления (нужно %d МБ)", APP_UPDATE_MANUAL = "Не удалось установить из приложения. Сохранено в %s: установите через VitaShell.", CHECKING = "Проверка...",
		NO_EXTENSIONS_HINT = "□ — вкладка «Доступные».", ALL_UP_TO_DATE = "Всё обновлено",
		NOTHING_HERE = "Здесь пусто", CHANGE_FILTERS_HINT = "Попробуйте другой язык (START) или поиск (△).",
		SEARCH_EXTENSIONS = "Поиск расширений", ALL_LANGUAGES = "Все языки", TAB = "Вкладка", REPOSITORIES = "Репозитории",
		REFRESH_REPOS = "Обновить репозитории", UPDATE_ALL = "Обновить все", ADD_REPO = "Добавить репозиторий", REPO_URL = "GitHub пользователь/репозиторий или URL index.json",
		REPO_EXISTS = "Репозиторий уже добавлен", REMOVE_REPO_Q = "Удалить %s?", REPO_BUILTIN = "Встроенный · онлайн", REPO_OFFLINE = "Встроенный · офлайн-копия",
		REPO_MIHON = "Репозиторий Mihon · в Otakio работают %d из %d источников", REPO_NEEDS_UPDATE = "%s требует более новую версию Otakio", N_REPOS = "Репозиториев: %d",
		LANG_EN = "Английский", LANG_PT = "Португальский", LANG_ES = "Испанский", LANG_FR = "Французский", LANG_DE = "Немецкий", LANG_IT = "Итальянский",
		LANG_RU = "Русский", LANG_JA = "Японский", LANG_ZH = "Китайский",
		LANG_MULTI = "Многоязычные", LANG_OTHER = "Другие",
		PROTECTED_CHAPTER = "Эта глава защищена сайтом и пока не поддерживается",
		-- import
		IMPORT_EMPTY = "Пока нечего импортировать",
		IMPORT_HELP = "Скопируйте в папку выше (FTP VitaShell или USB):\n• файл .cbz или .zip\n• папку с изображениями страниц\n• папку манги, где каждая глава — папка или .cbz\nЗатем ✕ — читать, □ — добавить в Библиотеку.",
		IMPORTED_N = "Импортировано: %d",
		-- settings / data
		PROXY_MODES = {Auto = "Только при необходимости", Off = "Выкл."}, PROXY_ADDRESS = "Адрес (IP:порт)",
		BACKUP_CREATED = "Копия сохранена:\n%s", BACKUP_FAILED = "Не удалось создать копию", BACKUP_INVALID = "Неверный файл копии",
		BACKUP_RESTORED = "Копия восстановлена (новых манг: %d)", NO_BACKUPS = "Нет копий в ux0:data/otakio/backups",
		RESTORE_BACKUP = "Восстановить копию", RESTORE_BACKUP_Q = "Восстановить эту копию?",
		IMPORT_NOBORU_Q = "Импортировать из NOBORU?", IMPORT_NOBORU_DESC = "Будут скопированы библиотека, прогресс чтения и парсеры.\nСкачанные главы останутся в исходной папке.",
		IMPORT_NOBORU_PARSERS = "Импорт классических Lua-парсеров", NOBORU_IMPORTED = "Импортировано манг: %d, парсеров: %d",
		NOBORU_NOT_FOUND = "Данные NOBORU не найдены (ux0:data/noboru)",
		-- about
		ABOUT_TAGLINE = "Читалка манги и комиксов для PS Vita",
		CREDITS_AUTHOR = "Автор", CREDITS_AI = "разработано с помощью ИИ (Claude, Anthropic)", CREDITS_BASED_ON = "Основано на", CREDITS_ENGINE = "Движок", CREDITS_SOURCES = "Источники",
		CREDITS_SOURCES_TEXT = "Темы и расширения адаптированы из проекта keiyoushi (Mihon)",
		CREDITS_TRANSLATIONS = "Переводы", CREDITS_REVISED = "доработаны для Otakio",
		CREDITS_SUPPORT = "Поддержите авторов: покупайте официальные издания."
	}
}
