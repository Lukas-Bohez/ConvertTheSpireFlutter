import 'package:shared_preferences/shared_preferences.dart';

/// Manages persistent storage of recently opened folders
class FolderHistoryService {
  static const String _lastFolderKey = 'file_browser_last_folder';
  static const String _favoritesFoldersKey = 'file_browser_favorites';

  static final FolderHistoryService _instance = FolderHistoryService._internal();

  factory FolderHistoryService() {
    return _instance;
  }

  FolderHistoryService._internal();

  /// Get the last opened folder path
  Future<String?> getLastFolder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastFolderKey);
  }

  /// Save the last opened folder path
  Future<void> saveLastFolder(String folderPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastFolderKey, folderPath);
  }

  /// Add a folder to favorites (optional)
  Future<void> addFavoriteFolder(String folderPath) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList(_favoritesFoldersKey) ?? [];
    if (!favorites.contains(folderPath)) {
      favorites.add(folderPath);
      await prefs.setStringList(_favoritesFoldersKey, favorites);
    }
  }

  /// Get list of favorite folders
  Future<List<String>> getFavoriteFolders() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_favoritesFoldersKey) ?? [];
  }

  /// Clear all history
  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastFolderKey);
    await prefs.remove(_favoritesFoldersKey);
  }
}
