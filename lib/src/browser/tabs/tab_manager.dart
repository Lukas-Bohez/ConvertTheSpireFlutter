import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// State for a single browser tab.
class BrowserTab {
  final String id;
  String url;
  String title;
  String? favicon;
  bool isIncognito;
  bool isLoading;
  /// Path to cached screenshot file, or null.
  String? screenshotPath;

  BrowserTab({
    required this.id,
    this.url = '',
    this.title = 'New Tab',
    this.favicon,
    this.isIncognito = false,
    this.isLoading = false,
    this.screenshotPath,
  });
}

/// Manages multiple browser tabs.
class TabManager extends ChangeNotifier {
  final List<BrowserTab> _tabs = [];
  int _activeIndex = 0;
  final Map<String, Uint8List?> _screenshotCache = {};

  List<BrowserTab> get tabs => List.unmodifiable(_tabs);
  int get activeIndex => _activeIndex;
  int get tabCount => _tabs.length;

  BrowserTab? get activeTab =>
      _tabs.isEmpty ? null : _tabs[_activeIndex.clamp(0, _tabs.length - 1)];

  TabManager() {
    // Start with one empty tab.
    _tabs.add(BrowserTab(id: _nextId()));
  }

  int _idCounter = 0;
  String _nextId() => 'tab_${++_idCounter}';

  /// Open a new tab and make it active.
  BrowserTab addTab({bool incognito = false, String? url}) {
    final tab = BrowserTab(
      id: _nextId(),
      isIncognito: incognito,
      url: url ?? '',
    );
    _tabs.add(tab);
    _activeIndex = _tabs.length - 1;
    notifyListeners();
    return tab;
  }

  /// Close a tab. If it was the last, create a new empty one.
  void closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    _tabs.removeAt(index);
    if (_tabs.isEmpty) {
      _tabs.add(BrowserTab(id: _nextId()));
      _activeIndex = 0;
    } else if (_activeIndex >= _tabs.length) {
      _activeIndex = _tabs.length - 1;
    }
    notifyListeners();
  }

  void switchToTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    _activeIndex = index;
    notifyListeners();
  }

  void updateTab(String tabId,
      {String? url, String? title, String? favicon, bool? isLoading}) {
    final tab = _tabs.firstWhere((t) => t.id == tabId, orElse: () => _tabs.first);
    if (url != null) tab.url = url;
    if (title != null) tab.title = title;
    if (favicon != null) tab.favicon = favicon;
    if (isLoading != null) tab.isLoading = isLoading;
    notifyListeners();
  }

  /// Store screenshot bytes to a temp file and save the path on the tab.
  Future<void> setScreenshot(String tabId, Uint8List? data) async {
    try {
      final tab = _tabs.firstWhere((t) => t.id == tabId);
      // Remove existing file if clearing or replacing.
      if (tab.screenshotPath != null) {
        try {
          final f = File(tab.screenshotPath!);
          if (await f.exists()) await f.delete();
        } catch (_) {}
        tab.screenshotPath = null;
      }

      // Keep latest bytes in memory for fast UI rendering regardless of file writes.
      _screenshotCache[tab.id] = data;
      if (data == null) {
        debugPrint('[TabManager] cleared screenshot for ${tab.id}');
        notifyListeners();
        return;
      }

      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final filePath = p.join(dir.path, 'tab_screenshot_${tab.id}_$ts.png');
      final file = File(filePath);
      await file.writeAsBytes(data, flush: true);
      // Do not rely on a stable filename; set a unique path so UI can
      // detect updates when screenshots are overwritten frequently.
      tab.screenshotPath = file.path;
      debugPrint('[TabManager] wrote screenshot for ${tab.id} -> ${file.path}');
      notifyListeners();
    } catch (_) {}
  }

  /// Return latest in-memory screenshot bytes for [tabId], if available.
  Uint8List? getScreenshotBytes(String tabId) => _screenshotCache[tabId];
}
