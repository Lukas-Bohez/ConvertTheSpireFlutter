import 'package:flutter/foundation.dart';

/// State for a single browser tab.
class BrowserTab {
  final String id;
  String url;
  String title;
  String? favicon;
  bool isIncognito;
  bool isLoading;
  Uint8List? screenshot;

  BrowserTab({
    required this.id,
    this.url = '',
    this.title = 'New Tab',
    this.favicon,
    this.isIncognito = false,
    this.isLoading = false,
    this.screenshot,
  });
}

/// Manages multiple browser tabs.
class TabManager extends ChangeNotifier {
  final List<BrowserTab> _tabs = [];
  int _activeIndex = 0;

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

  void setScreenshot(String tabId, Uint8List? data) {
    try {
      final tab = _tabs.firstWhere((t) => t.id == tabId);
      tab.screenshot = data;
    } catch (_) {}
  }
}
