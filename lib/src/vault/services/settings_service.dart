import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:convert_the_spire_reborn/src/vault/constants.dart';

class SettingsService {
  static final ValueNotifier<bool> persistentSidebarListenable =
      ValueNotifier<bool>(false);

  static String _defaultOllamaUrl() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return kAndroidLocalOllamaUrl;
    }
    return 'http://localhost:11434';
  }

  static const _kUseSystemTray = 'use_system_tray';
  static const _kMinimizeToTrayOnClose = 'minimize_to_tray_on_close';
  static const _kLaunchOnStartup = 'launch_on_startup';
  static const _kSoundEffectsEnabled = 'sound_effects_enabled';
  static const _kUsePersistentSidebar = 'use_persistent_sidebar';
  static const _kDownloadDestination = 'download_destination';
  static const _kDisplayName = 'display_name';
  static const _kWindowX = 'window_x';
  static const _kWindowY = 'window_y';
  static const _kWindowW = 'window_w';
  static const _kWindowH = 'window_h';
  static const _kTorrentSortMode = 'torrent_sort_mode';
  static const _kBrowserHomeUrl = 'browser_home_url';
  static const _kBrowserFavorites = 'browser_favorites';
  static const _kBrowserLastUrl = 'browser_last_url';
  static const _kBrowserHistory = 'browser_history';
  static const _kAiOllamaUrl = 'ai_ollama_url';
  static const _kAiDefaultModel = 'ai_default_model';
  static const _kAutoStartOnAdd = 'auto_start_on_add';
  static const _kUseDht = 'use_dht';
  static const _kUsePex = 'use_pex';
  static const _kUseLpd = 'use_lpd';
  static const _kListenPort = 'listen_port';
  static const _kMaxConnectionsGlobal = 'max_connections_global';
  static const _kMaxConnectionsPerTorrent = 'max_connections_per_torrent';
  static const _kMaxActiveDownloads = 'max_active_downloads';
  static const _kDownloadRateLimitKib = 'download_rate_limit_kib';
  static const _kUploadRateLimitKib = 'upload_rate_limit_kib';
  static const _kAllowSeedingAfterComplete = 'allow_seeding_after_complete';
  static const _kMaxSeedingRatio = 'max_seeding_ratio';
  static const _kEnableAiCopilot = 'enable_ai_copilot';
  static const _kEnableSmartSuggestions = 'enable_smart_suggestions';
  static const _kCompactTorrentRows = 'compact_torrent_rows';
  static const _kConfirmOnExit = 'confirm_on_exit';
  static const _kLastDiagnosticsExport = 'last_diagnostics_export';

  static final SettingsService instance = SettingsService._();
  SettingsService._();

  bool useSystemTray = true;
  bool minimizeToTrayOnClose = true;
  bool launchOnStartup = false;
  bool soundEffectsEnabled = true;
  bool usePersistentSidebar = false;
  String downloadDestination = '';
  int torrentSortMode = 0;
  String browserHomeUrl = 'https://www.startpage.com/';
  List<String> browserFavorites = <String>[
    'https://www.startpage.com/',
    'https://news.ycombinator.com/',
    'https://www.wikipedia.org/',
  ];
  String displayName = 'Anonymous';
  double windowX = 0.0;
  double windowY = 0.0;
  double windowW = 0.0;
  double windowH = 0.0;
  String browserLastUrl = '';
  List<String> browserHistory = <String>[];
  String aiOllamaUrl = _defaultOllamaUrl();
  String aiDefaultModel = kDefaultAiModel;
  bool autoStartOnAdd = true;
  bool useDht = true;
  bool usePex = true;
  bool useLpd = false;
  int listenPort = 6881;
  int maxConnectionsGlobal = 300;
  int maxConnectionsPerTorrent = 80;
  int maxActiveDownloads = 3;
  int downloadRateLimitKib = 0;
  int uploadRateLimitKib = 0;
  bool allowSeedingAfterComplete = true;
  double maxSeedingRatio = 1.5;
  bool enableAiCopilot = true;
  bool enableSmartSuggestions = true;
  bool compactTorrentRows = false;
  bool confirmOnExit = true;
  String lastDiagnosticsExport = '';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      displayName = prefs.getString(_kDisplayName) ?? 'Anonymous';
      useSystemTray = prefs.getBool(_kUseSystemTray) ?? true;
      minimizeToTrayOnClose = prefs.getBool(_kMinimizeToTrayOnClose) ?? true;
      launchOnStartup = prefs.getBool(_kLaunchOnStartup) ?? false;
      soundEffectsEnabled = prefs.getBool(_kSoundEffectsEnabled) ?? true;
      usePersistentSidebar = prefs.getBool(_kUsePersistentSidebar) ?? false;
      persistentSidebarListenable.value = usePersistentSidebar;
      downloadDestination = prefs.getString(_kDownloadDestination) ?? '';
      windowX = prefs.getDouble(_kWindowX) ?? 0.0;
      windowY = prefs.getDouble(_kWindowY) ?? 0.0;
      windowW = prefs.getDouble(_kWindowW) ?? 0.0;
      windowH = prefs.getDouble(_kWindowH) ?? 0.0;
      torrentSortMode = prefs.getInt(_kTorrentSortMode) ?? 0;
      browserHomeUrl = prefs.getString(_kBrowserHomeUrl) ?? browserHomeUrl;
      browserFavorites =
          prefs.getStringList(_kBrowserFavorites) ?? browserFavorites;
      browserLastUrl = prefs.getString(_kBrowserLastUrl) ?? '';
      browserHistory = prefs.getStringList(_kBrowserHistory) ?? <String>[];
      aiOllamaUrl = prefs.getString(_kAiOllamaUrl) ?? _defaultOllamaUrl();
      aiDefaultModel = prefs.getString(_kAiDefaultModel) ?? kDefaultAiModel;
      autoStartOnAdd = prefs.getBool(_kAutoStartOnAdd) ?? true;
      useDht = prefs.getBool(_kUseDht) ?? true;
      usePex = prefs.getBool(_kUsePex) ?? true;
      useLpd = prefs.getBool(_kUseLpd) ?? false;
      listenPort = prefs.getInt(_kListenPort) ?? 6881;
      maxConnectionsGlobal = prefs.getInt(_kMaxConnectionsGlobal) ?? 300;
      maxConnectionsPerTorrent = prefs.getInt(_kMaxConnectionsPerTorrent) ?? 80;
      maxActiveDownloads = prefs.getInt(_kMaxActiveDownloads) ?? 3;
      downloadRateLimitKib = prefs.getInt(_kDownloadRateLimitKib) ?? 0;
      uploadRateLimitKib = prefs.getInt(_kUploadRateLimitKib) ?? 0;
      allowSeedingAfterComplete =
          prefs.getBool(_kAllowSeedingAfterComplete) ?? true;
      maxSeedingRatio = prefs.getDouble(_kMaxSeedingRatio) ?? 1.5;
      enableAiCopilot = prefs.getBool(_kEnableAiCopilot) ?? true;
      enableSmartSuggestions = prefs.getBool(_kEnableSmartSuggestions) ?? true;
      compactTorrentRows = prefs.getBool(_kCompactTorrentRows) ?? false;
      confirmOnExit = prefs.getBool(_kConfirmOnExit) ?? true;
      lastDiagnosticsExport = prefs.getString(_kLastDiagnosticsExport) ?? '';
    } catch (_) {}
  }

  Future<void> setUseSystemTray(bool value) async {
    useSystemTray = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kUseSystemTray, value);
  }

  Future<void> setMinimizeToTrayOnClose(bool value) async {
    minimizeToTrayOnClose = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMinimizeToTrayOnClose, value);
  }

  Future<void> setLaunchOnStartup(bool value) async {
    launchOnStartup = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLaunchOnStartup, value);
  }

  Future<void> setSoundEffectsEnabled(bool value) async {
    soundEffectsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSoundEffectsEnabled, value);
  }

  Future<void> setUsePersistentSidebar(bool value) async {
    usePersistentSidebar = value;
    persistentSidebarListenable.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kUsePersistentSidebar, value);
  }

  Future<void> setDownloadDestination(String destination) async {
    downloadDestination = destination;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDownloadDestination, destination);
  }

  Future<void> setDisplayName(String name) async {
    displayName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDisplayName, name);
  }

  Future<void> setWindowGeometry(double x, double y, double w, double h) async {
    final prefs = await SharedPreferences.getInstance();
    windowX = x;
    windowY = y;
    windowW = w;
    windowH = h;
    await prefs.setDouble(_kWindowX, x);
    await prefs.setDouble(_kWindowY, y);
    await prefs.setDouble(_kWindowW, w);
    await prefs.setDouble(_kWindowH, h);
  }

  Future<void> setTorrentSortMode(int value) async {
    torrentSortMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kTorrentSortMode, value);
  }

  Future<void> setBrowserHomeUrl(String url) async {
    browserHomeUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBrowserHomeUrl, url);
  }

  Future<void> setBrowserFavorites(List<String> list) async {
    browserFavorites = list;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kBrowserFavorites, list);
  }

  Future<void> setBrowserLastUrl(String url) async {
    browserLastUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBrowserLastUrl, url);
  }

  Future<void> setBrowserHistory(List<String> history) async {
    browserHistory = history;
    final prefs = await SharedPreferences.getInstance();
    // Keep at most 200 entries persisted.
    final trimmed = history.length > 200 ? history.sublist(0, 200) : history;
    await prefs.setStringList(_kBrowserHistory, trimmed);
  }

  Future<void> setAiOllamaUrl(String url) async {
    aiOllamaUrl = url.trim().isEmpty ? _defaultOllamaUrl() : url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAiOllamaUrl, aiOllamaUrl);
  }

  Future<void> setAiDefaultModel(String model) async {
    aiDefaultModel = model.trim().isEmpty ? kDefaultAiModel : model.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAiDefaultModel, aiDefaultModel);
  }

  Future<void> setAutoStartOnAdd(bool value) async {
    autoStartOnAdd = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoStartOnAdd, value);
  }

  Future<void> setUseDht(bool value) async {
    useDht = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kUseDht, value);
  }

  Future<void> setUsePex(bool value) async {
    usePex = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kUsePex, value);
  }

  Future<void> setUseLpd(bool value) async {
    useLpd = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kUseLpd, value);
  }

  Future<void> setListenPort(int value) async {
    listenPort = value.clamp(1024, 65535);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kListenPort, listenPort);
  }

  Future<void> setMaxConnectionsGlobal(int value) async {
    maxConnectionsGlobal = value < 10 ? 10 : value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kMaxConnectionsGlobal, maxConnectionsGlobal);
  }

  Future<void> setMaxConnectionsPerTorrent(int value) async {
    maxConnectionsPerTorrent = value < 5 ? 5 : value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kMaxConnectionsPerTorrent, maxConnectionsPerTorrent);
  }

  Future<void> setMaxActiveDownloads(int value) async {
    maxActiveDownloads = value < 1 ? 1 : value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kMaxActiveDownloads, maxActiveDownloads);
  }

  Future<void> setDownloadRateLimitKib(int value) async {
    downloadRateLimitKib = value < 0 ? 0 : value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDownloadRateLimitKib, downloadRateLimitKib);
  }

  Future<void> setUploadRateLimitKib(int value) async {
    uploadRateLimitKib = value < 0 ? 0 : value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kUploadRateLimitKib, uploadRateLimitKib);
  }

  Future<void> setAllowSeedingAfterComplete(bool value) async {
    allowSeedingAfterComplete = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAllowSeedingAfterComplete, value);
  }

  Future<void> setMaxSeedingRatio(double value) async {
    maxSeedingRatio = value <= 0 ? 0 : value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kMaxSeedingRatio, maxSeedingRatio);
  }

  Future<void> setEnableAiCopilot(bool value) async {
    enableAiCopilot = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnableAiCopilot, value);
  }

  Future<void> setEnableSmartSuggestions(bool value) async {
    enableSmartSuggestions = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnableSmartSuggestions, value);
  }

  Future<void> setCompactTorrentRows(bool value) async {
    compactTorrentRows = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCompactTorrentRows, value);
  }

  Future<void> setConfirmOnExit(bool value) async {
    confirmOnExit = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kConfirmOnExit, value);
  }

  Future<void> setLastDiagnosticsExport(String value) async {
    lastDiagnosticsExport = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastDiagnosticsExport, value);
  }

  Future<void> clearBrowserHistory() async {
    browserHistory = <String>[];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kBrowserHistory);
  }
}
