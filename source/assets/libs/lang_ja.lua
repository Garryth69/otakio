---日本語
Language.Japanese = {
	APP = {LIBRARY = "ライブラリ", CATALOGS = "さがす", SETTINGS = "設定", DOWNLOAD = "ダウンロード", HISTORY = "履歴", IMPORT = "インポート", SEARCH = "検索"},
	DETAILS = {
		ADD_TO_LIBRARY = "ライブラリに追加", REMOVE_FROM_LIBRARY = "ライブラリから削除", CONTINUE = "続きを読む", START = "読み始める",
		DONE = "読了！", EXPAND = "もっと見る", SHRINK = "閉じる", PAGE = "ページ: ", SUMMARY = "あらすじ"
	},
	EXTRA = {DownloadAll = "全話をダウンロード", RemoveAll = "ダウンロード済みの話を削除", CancelAll = "ダウンロードを中止"},
	IMPORT = {DRIVE = "ドライブ", EXTERNAL_MEMORY = "外部メモリー", FILE = "ファイル", FOLDER = "フォルダー", GOBACK = "戻る", UNSUPFILE = "非対応のファイル"},
	MESSAGE = {
		LOST_CONNECTION = "接続が切れました\n\nネットワークを待っています…\n\n（アプリを最小化し、Wi-Fi設定を開いて「接続」を押してください）\n\n✕ボタンで全ダウンロードを中止してこのメッセージを閉じます。\nネットワークが戻るとダウンロードを再開します。",
		NO_CATALOG_MANGA = "見つかりませんでした。\nサイト、接続、またはソースのエラーです。",
		NO_DOWNLOADING_MANGA = "ダウンロードはありません"
	},
	MODES = {Popular = "人気", Latest = "最新", Alphabet = "名前順", ByLetter = "文字で", ByTag = "ジャンル", Search = "検索"},
	NOTIFICATIONS = {
		ADDED_TO_LIBRARY = "ライブラリに追加しました", REMOVED_FROM_LIBRARY = "ライブラリから削除しました", BAD_IMAGE_FOUND = "壊れた画像があります",
		CACHE_CLEARED = "キャッシュを消去しました", CHAPTERS_CLEARED = "ダウンロード済みの話をすべて削除しました", CHAPTER_REMOVE = "%s を削除しました",
		COVER_SET_COMPLETED = "表紙を更新しました", IMPORT_COMPLETED = "インポート完了", LIBRARY_CLEARED = "ライブラリを消去しました",
		NET_PROBLEM = "接続の問題", NO_SPACE_LEFT = "空き容量が足りません", REFRESH_COMPLETED = "更新完了",
		SEARCHING = "「%s」を検索中", SETTINGS_RESET = "設定をリセットしました",
		START_DOWNLOAD = "%s: %s\nダウンロード開始", END_DOWNLOAD = "%s: %s\nダウンロード完了", CANCEL_DOWNLOAD = "%s: %s\nダウンロード中止"
	},
	NSFW = {[true] = "表示", [false] = "非表示"},
	YORN = {[true] = "はい", [false] = "いいえ"},
	PAGINGCONTROLS = {DPAD = "方向キー", LR = "L・Rボタン"},
	PANEL = {
		BACK = "戻る", CANCEL = "キャンセル", CHANGE_SECTION = "セクション", DELETE = "削除", IMPORT = "インポート", MODE = "モード",
		READ = "読む", SEARCH = "検索", SELECT = "選択", UPDATE = "更新"
	},
	PARSERS = {
		DIF = "すべての言語", ENG = "英語", BRA = "ポルトガル語（ブラジル）", PRT = "ポルトガル語", ESP = "スペイン語", FRA = "フランス語",
		DEU = "ドイツ語", ITA = "イタリア語", RUS = "ロシア語", JAP = "日本語", KOR = "韓国語", CHN = "中国語", IDN = "インドネシア語",
		POL = "ポーランド語", ROU = "ルーマニア語", TUR = "トルコ語", VIE = "ベトナム語", RAW = "RAW（未翻訳）", ARA = "アラビア語",
		BUL = "ブルガリア語", CES = "チェコ語", FAS = "ペルシア語", FIL = "フィリピン語", HIN = "ヒンディー語", HUN = "ハンガリー語", MSA = "マレー語",
		MYA = "ビルマ語", NLD = "オランダ語", THA = "タイ語", UKR = "ウクライナ語"
	},
	READER = {
		Horizontal = "横", Vertical = "縦", Smart = "スマート", Height = "高さに合わせる", Width = "幅に合わせる", Default = "標準",
		LEFT = "右から左", RIGHT = "左から右", DOWN = "上から下",
		LOADING_PAGE = "ページを読み込み中", LOADING_SEGMENT = "部分を読み込み中", PREPARING_PAGES = "ページを準備中"
	},
	SETTINGS = {
		SourceLanguages = "有効な言語",
		MainSettingsMenu = "その他", Language = "言語", ChangeUI = "テーマ", Library = "ライブラリ", Catalogs = "さがす",
		ExtensionsSettings = "拡張機能", Reader = "リーダー", Network = "ネットワーク", Data = "データ", Other = "その他",
		Controls = "操作", About = "情報",
		LibrarySorting = "ライブラリの並べ替え", LibraryFilter = "ライブラリの絞り込み", EditCategories = "カテゴリー",
		RefreshLibAtStart = "起動時にライブラリを更新", AutoDownloadNew = "新しい話を自動でダウンロード",
		ShowNSFW = "成人向け（18+）ソースを表示", HideInOffline = "オフライン時はダウンロード済みのみ表示", PreferredCatalogLanguage = "ソースの言語",
		ExtensionRepos = "リポジトリ", CheckExtUpdatesAtStart = "起動時に拡張機能の更新を確認",
		AutoUpdateExtensions = "拡張機能を自動で更新", ImportNoboruParsers = "従来のLuaパーサーをインポート",
		ReaderOrientation = "リーダーの向き", ZoomReader = "ページの拡大縮小", ReaderDirection = "読む方向",
		DoubleTapReader = "ダブルタップでズーム", PressEdgesToChangePage = "端をタップしてページ送り", PreloadPages = "先読みするページ数",
		Incognito = "シークレットモード", SaveImageFormat = "画像の保存形式", ConnectionTime = "接続タイムアウト（秒）", ImageProxy = "画像変換（wsrv.nl）",
		DataSaver = "データセーバー", Proxy = "プロキシ", UseProxy = "プロキシを使う", UseProxyAuth = "プロキシ認証", ProxyAuth = "ユーザー:パスワード",
		CreateBackup = "バックアップを作成", RestoreBackup = "バックアップを復元", ImportNoboruData = "NOBORUからインポート",
		SaveDataPath = "ダウンロードの保存先", ClearLibrary = "ライブラリを消去", ClearCache = "キャッシュを消去（ライブラリ外の作品）",
		ClearAllCache = "すべてのキャッシュを消去", ClearChapters = "ダウンロード済みの話をすべて削除", ResetAllSettings = "すべての設定をリセット",
		SkipFontLoading = "フォントの先読みを省略", ChapterSorting = "話の並び順", SilentDownloads = "ダウンロード通知を隠す",
		SkipCacheChapterChecking = "起動時のキャッシュ確認を省略", LoadSummary = "あらすじを表示", ShowFPS = "FPSを表示",
		ShowVersion = "バージョン", CheckAppUpdate = "アプリの更新を確認", AppAutoUpdate = "起動時にアプリの更新を確認", SwapXO = "決定ボタン", ChangingPageButtons = "ページ送りボタン",
		LeftStickDeadZone = "左スティックのデッドゾーン", LeftStickSensitivity = "左スティックの感度",
		RightStickDeadZone = "右スティックのデッドゾーン", RightStickSensitivity = "右スティックの感度",
		EU = "×（海外式）", JP = "○（日本式）", InputValue = "値を入力", NoConnection = "接続なし",
		PressAgainToAccept = "もう一度押して確定", ResetCover = "表紙を元に戻す", SetPageAsCover = "このページを表紙にする",
		DownloadImageToMemory = "画像を保存"
	},
	SETTINGS_DESCRIPTION = {
		Library = "並べ替え、絞り込み、カテゴリー、更新", Catalogs = "言語、成人向けコンテンツ",
		ExtensionsSettings = "リポジトリ、自動更新", Reader = "方向、向き、ズーム",
		Network = "タイムアウト、画像変換、プロキシ", Data = "バックアップ、キャッシュ、保存先", Other = "フォント、話の並び順、通知",
		Controls = "ボタンとアナログスティック", About = "バージョンとクレジット",
		AutoDownloadNew = "ライブラリ更新のあとに", PreloadPages = "次のページを裏でダウンロード",
		Incognito = "履歴と進捗を保存しません", SaveImageFormat = "リーダーの「画像を保存」用。別の形式への変換には数秒かかります", ImageProxy = "Vitaで開けない形式のみ（AVIF、JXL、GIF）",
		DataSaver = "プロキシ経由で画像を小さく（960px）", ImportNoboruData = "ライブラリ、進捗、パーサー"
	},
	THEME = {Otakio = "Otakio（ダークパープル）", AMOLED = "AMOLEDブラック", Dark = "ダーク", Ocean = "オーシャン", Matcha = "抹茶", Crimson = "クリムゾン", Sakura = "桜（ライト）", Light = "ライト"},
	WARNINGS = {NO_CHAPTERS = "話がありません"},
	OTAKIO = {
		REPO_UNOFFICIAL_Q = "サードパーティのリポジトリを追加しますか？", REPO_UNOFFICIAL_MSG = "拡張機能はアプリ内で動くプログラムです。\n信頼できるリポジトリだけを追加してください。",
		SETUP_INSTALL_RECOMMENDED = "おすすめのソースをインストール", SETUP_INSTALL_RECOMMENDED_SUB = "リポジトリ Garryth69/otakio-extensions を追加します", RECOMMENDED_QUEUED = "おすすめのソースを%d件インストール中", RECOMMENDED_NONE = "拡張機能リポジトリを読み込めません（接続を確認してください）。拡張機能 > リポジトリ でもう一度お試しください", RECOMMENDED_ALL_INSTALLED = "おすすめのソースはすでにインストールされています", RECOMMENDED_NONE_LANG = "選択した言語のおすすめソースはありません", SAVE_FORMAT_ORIGINAL = "元の形式",
		REMOVED_FROM_REPO = "リポジトリから削除済み・まだ使えますがアンインストールできます",
		SETUP_STEP = "初期設定 %d/%d", SETUP_LANG_HINT = "メニューとボタンの言語。", SETUP_EXTLANG_HINT = "拡張機能と閲覧にはこの言語だけが表示されます。\n何も選ばない＝すべての言語。", SETUP_NSFW_HINT = "成人向けソースは許可しない限り表示されません。", SETUP_DIRECTION_HINT = "漫画：右から左。コミック：左から右。\nWebtoon：上から下。", SETUP_ORIENTATION_HINT = "読むときのVitaの持ち方。", SETUP_KEYS_HINT = "決定ボタン（もう一方は戻る）。", SETUP_DONE_TITLE = "準備完了！", SETUP_DONE = "拡張機能からソースをインストールしてください。\n設定はあとで「その他」から変更できます。", SETUP_FINISH = "完了",
		NAV = {LIBRARY = "ライブラリ", UPDATES = "更新", HISTORY = "履歴", BROWSE = "さがす", EXTENSIONS = "拡張機能", DOWNLOADS = "DL", IMPORT = "インポート", MORE = "その他"},
		LIBRARY = "ライブラリ", UPDATES = "更新", HISTORY = "履歴", BROWSE = "さがす", EXTENSIONS = "拡張機能",
		DOWNLOADS = "ダウンロード", IMPORT = "インポート", MORE = "その他", GLOBAL_SEARCH = "まとめて検索",
		ALL = "すべて", AUTHOR = "作者", ARTIST = "作画", STATUS = "状態", GENRES = "ジャンル", N_CHAPTERS = "%d話",
		JUST_NOW = "たった今", MINUTES_AGO = "%d分前", HOURS_AGO = "%d時間前", DAYS_AGO = "%d日前", TODAY = "今日", YESTERDAY = "昨日",
		YES = "はい", NO = "いいえ", OFF = "オフ",
		HINT_TOGGLE_APPLY = "× 切り替え   ○ / △ 適用", HINT_SELECT_BACK = "× 選択   ○ 戻る",
		STATUS_OK = "動作中", STATUS_UNSTABLE = "不安定", STATUS_BROKEN = "動作しません",
		-- library
		LIBRARY_EMPTY = "ライブラリは空です", LIBRARY_EMPTY_HINT = "「さがす」で作品を見つけてSTARTを押すと\nライブラリに追加できます。",
		LIBRARY_FILTER_EMPTY = "条件に合う作品がありません", LIBRARY_FILTER_EMPTY_HINT = "STARTで並べ替え・絞り込み、□でカテゴリーを切り替え。",
		LIBRARY_OPTIONS = "ライブラリのオプション", SORT_BY = "並べ替え", FILTER = "絞り込み",
		SORT_NAMES = {["Date added"] = "追加日", ["A-Z"] = "A → Z", ["Z-A"] = "Z → A", Unread = "未読数", ["Last read"] = "最後に読んだ日", ["Latest chapter"] = "最新話"},
		FILTER_NAMES = {All = "すべて", Unread = "未読", Downloaded = "ダウンロード済み", Completed = "読了"},
		EDIT_CATEGORIES = "カテゴリーを編集", SET_CATEGORIES = "カテゴリーを設定", N_CATEGORIES = "%d個のカテゴリー", ADD_CATEGORY = "カテゴリーを追加",
		CATEGORY_NAME = "カテゴリー名", RENAME = "名前を変更", MOVE_UP = "上へ", MOVE_DOWN = "下へ", DELETE = "削除",
		DELETE_CATEGORY_Q = "このカテゴリーを削除しますか？", REFRESH_LIBRARY = "ライブラリを更新", REFRESHING = "更新中 %d/%d",
		CATEGORY = "カテゴリー", OPTIONS = "オプション", CONTINUE_READING = "続きを読む", IN_LIBRARY = "ライブラリ内", ADD_REMOVE = "ライブラリ +/-",
		NEW_CHAPTERS_FOUND = "新しい話が%d件！",
		-- browse
		NO_SOURCES = "ソースがインストールされていません", NO_SOURCES_HINT = "拡張機能タブ（R）を開いて、使いたいソースを選んでください。",
		NO_SOURCES_LANG = "この言語のソースはありません", NO_SOURCES_LANG_HINT = "STARTで言語の絞り込みを変更できます。",
		PIN = "ピン留め", UNPIN = "ピン留めを外す", LANGUAGE = "言語", NEW = "NEW",
		NO_RESULTS = "結果がありません", SEARCHING_N = "検索中 %d/%d", OPEN_IN_SOURCE = "ソースで開く",
		NO_SOURCE_SEARCH = "このソースは検索に対応していません",
		-- updates / history
		NO_UPDATES = "最近の更新はありません", NO_UPDATES_HINT = "△ で新しい章を探します。",
		CLEAR_UPDATES_Q = "更新リストを消去しますか？", MANGA_NOT_FOUND = "ライブラリに作品が見つかりません", ALREADY_DOWNLOADED = "ダウンロード済み",
		NO_HISTORY = "最近読んだ作品はありません", NO_HISTORY_HINT = "読んだ話がここに表示されます。",
		RESUME = "再開", START = "開始", INCOGNITO_ON = "シークレットモードがオンです", DETAILS = "詳細", DOWNLOAD = "ダウンロード", CLEAR = "消去",
		-- downloads
		DOWNLOADS_HINT = "話の上で□、作品ページでSTARTを押すとダウンロードします。", PREPARING = "準備中…", QUEUED = "待機中",
		QUEUED_N = "%d話が待機中", CANCEL_ALL = "すべて中止", DOWNLOADED_N = "ダウンロード済み（%d）",
		MARK_ALL_READ = "すべて既読にする", MARK_ALL_UNREAD = "すべて未読にする", MARK_PREVIOUS_READ = "これより前を既読にする",
		DOWNLOAD_NEXT_5 = "次の未読5話をダウンロード", DOWNLOAD_UNREAD = "未読をすべてダウンロード",
		-- extensions
		INSTALLED = "インストール済み", AVAILABLE = "利用可能", UPDATES_TAB = "アップデート", INSTALL = "インストール", UPDATE = "アップデート", INSTALLED_LABEL = "インストール済み",
		UNINSTALL = "アンインストール", UNINSTALL_Q = "%s をアンインストールしますか？", OPEN_SOURCE = "ソースを開く", SOURCE_HIDDEN = "ソースを利用できません（成人向けがオフか、拡張機能の読み込みに失敗）",
		EXT_INSTALLED = "%s をインストールしました", EXT_UPDATED = "%s をアップデートしました", EXT_UNINSTALLED = "%s をアンインストールしました", EXT_INSTALL_FAILED = "%s をインストールできませんでした",
		EXT_UPDATES_AVAILABLE = "拡張機能のアップデート: %d件", NO_EXTENSIONS = "拡張機能がインストールされていません", NO_PAGES = "この話にはまだページがありません", ERROR_RECOVERED = "問題が発生したため、ライブラリに戻りました（詳細はlog.txt）", NO_REPOS = "拡張機能のリポジトリがありません", NO_REPOS_HINT = "Otakioにはソースが内蔵されていません。SELECT > リポジトリを追加。", APP_UP_TO_DATE = "Otakioは最新です", APP_UPDATE_AVAILABLE = "Otakio %s が利用できます", APP_UPDATE_Q = "Otakio %s にアップデートしますか？", APP_UPDATE_HINT = "Otakioがダウンロードとインストールを行い、再起動します。ライブラリと設定はそのまま残ります。", APP_UPDATE_DOWNLOADING = "Otakio %s をダウンロード中...", APP_UPDATE_DONE = "%s に保存しました。VitaShellでインストールしてください。", APP_UPDATE_FAILED = "アップデートを確認できませんでした", APP_UPDATE_RESTARTING = "Otakio を閉じて %s をインストールし、自動で再起動します...", APP_UPDATE_DONE_NOW = "Otakio %s に更新しました", APP_UPDATE_DL_FAILED = "アップデートのダウンロードに失敗しました。後でもう一度お試しください。", APP_UPDATE_INSTALLING = "Otakio %s をインストール中...", APP_UPDATE_STEP = "ステップ %d / %d", APP_UPDATE_EXTRACTING = "アップデートを展開中...", APP_UPDATE_PREPARING = "インストーラーを準備中...", APP_UPDATE_DONT_OFF = "電源を切らないでください", APP_UPDATE_CANCEL = "キャンセル", APP_UPDATE_CANCELED = "アップデートをキャンセルしました", RS_TITLE = "リーダー設定", RS_THIS_MANGA = "このマンガ", RS_COLORS = "ページの色", RS_READER = "リーダー", RS_PAGE = "このページ", RS_BACKGROUND = "背景", RS_BG_THEME = "テーマ", RS_BG_BLACK = "黒", RS_BG_GRAY = "グレー", RS_BG_WHITE = "白", RS_BRIGHTNESS = "明るさ", RS_FILTER = "カラーフィルター", RS_PRESET = "プリセット", RS_PRESET_CUSTOM = "カスタム", RS_PRESET_SEPIA = "セピア", RS_PRESET_PAPER = "紙", RS_PRESET_WARM = "暖色", RS_PRESET_NIGHT = "夜間", RS_BLEND = "ブレンドモード", RS_BLEND_DEFAULT = "標準", RS_BLEND_MULTIPLY = "乗算", RS_RED = "赤", RS_GREEN = "緑", RS_BLUE = "青", RS_OPACITY = "不透明度", RS_PAGE_NUMBER = "ページ番号を表示", RS_RESET = "色をリセット", RS_ADJUST = "調整", RS_CLOSE = "閉じる", DL_VIEW_QUEUE = "キュー", DL_VIEW_DONE = "ダウンロード済み", DL_VIEW_HISTORY = "履歴", DL_VIEW = "表示", DL_QUEUE_EMPTY = "ダウンロード中の項目はありません", DL_HISTORY_EMPTY = "ダウンロード履歴はありません", DL_HISTORY_HINT = "完了・失敗・キャンセルしたダウンロードがここに表示されます。", DL_CLEAR_HISTORY = "履歴を消去", DL_CLEAR_HISTORY_Q = "ダウンロードした章は残ります。", DL_HISTORY_CLEARED = "ダウンロード履歴を消去しました", DL_STATUS_OK = "完了", DL_STATUS_FAILED = "失敗", DL_STATUS_CANCELED = "キャンセル", DL_REMOVE_ENTRY = "削除", DL_CHAPTERS = "章", DL_TAP_DELETE = "このダウンロードを削除", DL_DELETE_CHAPTER = "このダウンロード済みの章を削除しますか？", DATA_MIGRATION_FAILED = "データをこのバージョン用に更新できませんでした。データは元のままです（詳細は log.txt）", APP_UPDATE_INSTALLED = "Otakio %s をインストールしました。再起動します...", APP_UPDATE_NO_SPACE = "更新に必要な空き容量が足りません（%d MB 必要）", APP_UPDATE_MANUAL = "アプリ内でインストールできませんでした。%s に保存しました。VitaShellでインストールしてください。", CHECKING = "確認中...",
		NO_EXTENSIONS_HINT = "□で「利用可能」タブに切り替えます。", ALL_UP_TO_DATE = "すべて最新です",
		NOTHING_HERE = "ここには何もありません", CHANGE_FILTERS_HINT = "別の言語（START）か検索（△）を試してください。",
		SEARCH_EXTENSIONS = "拡張機能を検索", ALL_LANGUAGES = "すべての言語", TAB = "タブ", REPOSITORIES = "リポジトリ",
		REFRESH_REPOS = "リポジトリを更新", UPDATE_ALL = "すべてアップデート", ADD_REPO = "リポジトリを追加", REPO_URL = "GitHubのユーザー/リポジトリ、またはindex.jsonのURL",
		REPO_EXISTS = "このリポジトリは追加済みです", REMOVE_REPO_Q = "%s を削除しますか？", REPO_BUILTIN = "内蔵 · オンライン", REPO_OFFLINE = "内蔵 · オフラインコピー",
		REPO_MIHON = "Mihonリポジトリ · %d / %d 件のソースがOtakioで動作", REPO_NEEDS_UPDATE = "%s には新しいOtakioが必要です", N_REPOS = "%d個のリポジトリ",
		LANG_EN = "英語", LANG_PT = "ポルトガル語", LANG_ES = "スペイン語", LANG_FR = "フランス語", LANG_DE = "ドイツ語", LANG_IT = "イタリア語",
		LANG_RU = "ロシア語", LANG_JA = "日本語", LANG_ZH = "中国語",
		LANG_MULTI = "多言語", LANG_OTHER = "その他",
		PROTECTED_CHAPTER = "この話はサイトで保護されており、まだ対応していません",
		-- import
		IMPORT_EMPTY = "インポートするものがありません",
		IMPORT_HELP = "上のフォルダーにコピーしてください（VitaShellのFTPかUSB）:\n• .cbz または .zip ファイル\n• ページ画像の入ったフォルダー\n• 1話ごとにフォルダーか .cbz を入れた作品フォルダー\n✕で読み、□でライブラリに追加します。",
		IMPORTED_N = "%d件をインポートしました",
		-- settings / data
		PROXY_MODES = {Auto = "必要なときだけ", Off = "オフ"}, PROXY_ADDRESS = "アドレス（IP:ポート）",
		BACKUP_CREATED = "バックアップを保存しました:\n%s", BACKUP_FAILED = "バックアップを作成できませんでした", BACKUP_INVALID = "無効なバックアップファイル",
		BACKUP_RESTORED = "バックアップを復元しました（新しい作品%d件）", NO_BACKUPS = "ux0:data/otakio/backups にバックアップがありません",
		RESTORE_BACKUP = "バックアップを復元", RESTORE_BACKUP_Q = "このバックアップを復元しますか？",
		IMPORT_NOBORU_Q = "NOBORUからインポートしますか？", IMPORT_NOBORU_DESC = "ライブラリ、読書の進捗、パーサーをコピーします。\nダウンロード済みの話は元のフォルダーに残ります。",
		IMPORT_NOBORU_PARSERS = "従来のLuaパーサーをインポート", NOBORU_IMPORTED = "作品%d件とパーサー%d件をインポートしました",
		NOBORU_NOT_FOUND = "NOBORUのデータが見つかりません（ux0:data/noboru）",
		-- about
		ABOUT_TAGLINE = "PS Vita用のマンガ・コミックリーダー",
		CREDITS_AUTHOR = "作者", CREDITS_AI = "AIの支援で開発（Claude、Anthropic）", CREDITS_BASED_ON = "ベース", CREDITS_ENGINE = "エンジン", CREDITS_SOURCES = "ソース",
		CREDITS_SOURCES_TEXT = "テーマと拡張機能はkeiyoushi（Mihon）プロジェクトから移植",
		CREDITS_TRANSLATIONS = "翻訳", CREDITS_REVISED = "Otakio向けに改訂",
		CREDITS_SUPPORT = "作者を応援しよう：公式版を購入してください。"
	}
}
