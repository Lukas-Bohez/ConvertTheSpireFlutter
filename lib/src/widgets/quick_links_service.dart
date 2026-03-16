import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A single quick-link tile shown on the home/new-tab page.
class QuickLink {
  final String name;
  final IconData icon;
  final String route;
  final String description;

  const QuickLink({
    required this.name,
    required this.icon,
    required this.route,
    this.description = '',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'route': route,
        'description': description,
      };

  factory QuickLink.fromJson(Map<String, dynamic> json) {
    final route = json['route'] as String;
    return QuickLink(
      name: json['name'] as String,
      icon: _routeIcons[route] ?? Icons.link,
      route: route,
      description: json['description'] as String? ?? '',
    );
  }

  /// Constant icon lookup by route — avoids non-constant IconData construction.
  static const Map<String, IconData> _routeIcons = {
    'search.tab': Icons.search,
    'multisearch.tab': Icons.travel_explore,
    'browser.tab': Icons.open_in_browser,
    'queue.tab': Icons.queue_music,
    'playlists.tab': Icons.playlist_play,
    'bulkimport.tab': Icons.upload_file,
    'stats.tab': Icons.bar_chart,
    'settings.tab': Icons.settings,
    'support.tab': Icons.volunteer_activism,
    'convert.tab': Icons.transform,
    'logs.tab': Icons.list_alt,
    'guide.tab': Icons.menu_book,
    'player.tab': Icons.music_note,
  };
}

class QuickLinksService {
  static const _key = 'quick_links_v1';

  static const List<QuickLink> defaults = [
    QuickLink(
      name: 'Search',
      icon: Icons.search,
      route: 'search.tab',
      description: 'Download from YouTube URL',
    ),
    QuickLink(
      name: 'Multi-Search',
      icon: Icons.travel_explore,
      route: 'multisearch.tab',
      description: 'Search YouTube & SoundCloud',
    ),
    QuickLink(
      name: 'Browser',
      icon: Icons.language,
      route: 'browser.tab',
      description: 'In-app web browser',
    ),
    QuickLink(
      name: 'Playlists',
      icon: Icons.playlist_play,
      route: 'playlists.tab',
      description: 'YouTube playlists & folders',
    ),
    QuickLink(
      name: 'Bulk Import',
      icon: Icons.upload_file,
      route: 'bulkimport.tab',
      description: 'Import track lists',
    ),
    QuickLink(
      name: 'Stats',
      icon: Icons.bar_chart,
      route: 'stats.tab',
      description: 'Download statistics',
    ),
    QuickLink(
      name: 'Settings',
      icon: Icons.settings,
      route: 'settings.tab',
      description: 'App configuration',
    ),
    QuickLink(
      name: 'Support',
      icon: Icons.volunteer_activism,
      route: 'support.tab',
      description: 'Support via donations',
    ),
    QuickLink(
      name: 'Convert',
      icon: Icons.transform,
      route: 'convert.tab',
      description: 'Convert audio/video files',
    ),
    QuickLink(
      name: 'Logs',
      icon: Icons.list_alt,
      route: 'logs.tab',
      description: 'Activity log viewer',
    ),
    QuickLink(
      name: 'Guide',
      icon: Icons.menu_book,
      route: 'guide.tab',
      description: 'Help & documentation',
    ),
    QuickLink(
      name: 'Player',
      icon: Icons.music_note,
      route: 'player.tab',
      description: 'Media player & library',
    ),
  ];

  /// Route string → tab index mapping.
  static const Map<String, int> routeToIndex = {
    'search.tab': 0,
    'multisearch.tab': 1,
    'browser.tab': 2,
    'queue.tab': 3,
    'playlists.tab': 4,
    'bulkimport.tab': 5,
    'stats.tab': 6,
    'settings.tab': 7,
    'support.tab': 8,
    'convert.tab': 9,
    'logs.tab': 10,
    'guide.tab': 11,
    'player.tab': 12,
    'home': 13,
  };

  /// Tab index → route string mapping.
  static const Map<int, String> indexToRoute = {
    0: 'search.tab',
    1: 'multisearch.tab',
    2: 'browser.tab',
    3: 'queue.tab',
    4: 'playlists.tab',
    5: 'bulkimport.tab',
    6: 'stats.tab',
    7: 'settings.tab',
    8: 'support.tab',
    9: 'convert.tab',
    10: 'logs.tab',
    11: 'guide.tab',
    12: 'player.tab',
    13: 'home',
  };

  /// Tab index → page title for the fake URL bar.
  static const Map<int, String> indexToTitle = {
    0: 'Search',
    1: 'Search+',
    2: 'Browser',
    3: 'Queue',
    4: 'Playlists',
    5: 'Import',
    6: 'Stats',
    7: 'Settings',
    8: 'Support',
    9: 'Convert',
    10: 'Logs',
    11: 'Guide',
    12: 'Player',
    13: 'Home',
  };

  /// Tab index → favicon icon.
  static const Map<int, IconData> indexToIcon = {
    0: Icons.search,
    1: Icons.travel_explore,
    2: Icons.open_in_browser,
    3: Icons.queue_music,
    4: Icons.playlist_play,
    5: Icons.upload_file,
    6: Icons.bar_chart,
    7: Icons.settings,
    8: Icons.volunteer_activism,
    9: Icons.transform,
    10: Icons.list_alt,
    11: Icons.menu_book,
    12: Icons.music_note,
    13: Icons.home,
  };

  static const _hiddenRoutes = {'queue.tab'};

  static Future<List<QuickLink>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    List<QuickLink> links;
    if (json == null) {
      links = List.of(defaults);
    } else {
      try {
        final list = jsonDecode(json) as List;
        links = list
            .map((e) => QuickLink.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        links = List.of(defaults);
      }
    }
    // Always strip retired Browser/Queue tiles (may still be in saved prefs).
    links.removeWhere((l) => _hiddenRoutes.contains(l.route));
    return links;
  }

  static Future<void> save(List<QuickLink> links) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(links.map((e) => e.toJson()).toList()));
  }

  static Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
