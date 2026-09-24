import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

/// One release's entry from the changelog.
class WhatsNewEntry {
  /// Version as it appears in the changelog, e.g. `14.3.1`.
  final String version;

  /// The release's own title, e.g. `Watch Together polish`.
  final String title;

  /// The body, as Markdown, without the heading line.
  final String body;

  /// Releases between this one and the last one the person saw, newest
  /// first. Empty when this release is the only news.
  final List<WhatsNewEntry> earlier;

  const WhatsNewEntry({
    required this.version,
    required this.title,
    required this.body,
    this.earlier = const [],
  });
}

/// Shows people what changed after the app updates itself under them.
///
/// Releases went out with nobody noticing what was in them (issue #7). The
/// changelog is already written and kept current, so it is the source rather
/// than a second list that would drift.
class WhatsNewService {
  WhatsNewService._();

  static final WhatsNewService instance = WhatsNewService._();

  static const String _lastShownKey = 'whats_new_last_shown_version';
  static const String changelogAsset = 'CHANGELOG.md';

  String? _cachedChangelog;

  /// The first release with this dialog. A device that has used the app but
  /// has no record of a shown version was updated from something older, so
  /// every release from this one on is news to it.
  static const String firstVersionWithDialog = '14.4.0';

  /// The most releases shown at once, for somebody who skipped a lot of them.
  static const int maxEntries = 5;

  /// Every release section in a changelog, in the order they appear.
  ///
  /// Headings look like `## 14.3.1+1295 — Watch Together polish`; the build
  /// number and the dash are both optional, so a heading of just `## 14.3.1`
  /// is still found.
  static List<WhatsNewEntry> entries(String changelog) {
    final found = <WhatsNewEntry>[];
    final lines = changelog.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!line.startsWith('## ')) continue;

      final heading = line.substring(3).trim();
      final separator = RegExp(r'\s+[—–-]\s+');
      final match = separator.firstMatch(heading);
      final versionPart =
          (match == null ? heading : heading.substring(0, match.start)).trim();
      final title = match == null ? '' : heading.substring(match.end).trim();
      final version = _normaliseVersion(versionPart);
      if (version.isEmpty) continue;

      final body = StringBuffer();
      for (var j = i + 1; j < lines.length; j++) {
        if (lines[j].startsWith('## ')) break;
        body.writeln(lines[j]);
      }
      found.add(WhatsNewEntry(
        version: version,
        title: title,
        body: body.toString().trim(),
      ));
    }
    return found;
  }

  /// Parses one version's section out of a changelog.
  static WhatsNewEntry? entryFor(String changelog, String version) {
    final wanted = _normaliseVersion(version);
    if (wanted.isEmpty) return null;
    for (final entry in entries(changelog)) {
      if (entry.version == wanted) return entry;
    }
    return null;
  }

  /// [current]'s entry, carrying every release after [lastSeen] in
  /// [WhatsNewEntry.earlier].
  ///
  /// Showing only the newest release hid most of what changed from anyone
  /// who skipped one: 14.4.0 did not get past its loading screen, so nearly
  /// everybody went from 14.3.1 straight to 14.4.1, and would have read about
  /// a startup fix and nothing about extensions. With no [lastSeen], releases
  /// from [firstVersionWithDialog] on count as unseen.
  static WhatsNewEntry? entrySince(
    String changelog,
    String current, {
    String? lastSeen,
  }) {
    final newest = entryFor(changelog, current);
    if (newest == null) return null;
    final after = _normaliseVersion(lastSeen ?? '');

    final earlier = entries(changelog).where((entry) {
      if (_compareVersions(entry.version, newest.version) >= 0) return false;
      return after.isEmpty
          ? _compareVersions(entry.version, firstVersionWithDialog) >= 0
          : _compareVersions(entry.version, after) > 0;
    }).toList()
      ..sort((a, b) => _compareVersions(b.version, a.version));
    if (earlier.isEmpty) return newest;

    return WhatsNewEntry(
      version: newest.version,
      title: newest.title,
      body: newest.body,
      earlier: earlier.take(maxEntries - 1).toList(),
    );
  }

  /// Orders `14.10.0` after `14.9.2`, which a string comparison does not.
  static int _compareVersions(String a, String b) {
    final left = a.split('.');
    final right = b.split('.');
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final x = i < left.length ? int.tryParse(left[i]) ?? 0 : 0;
      final y = i < right.length ? int.tryParse(right[i]) ?? 0 : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  /// Strips a build number and any leading `v`, so `v14.3.1+1295` is `14.3.1`.
  static String _normaliseVersion(String raw) {
    var value = raw.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    final plus = value.indexOf('+');
    if (plus != -1) value = value.substring(0, plus);
    return value.trim();
  }

  /// The entry to show for [version], or null when there is nothing new.
  /// Releases the person skipped come along in [WhatsNewEntry.earlier].
  ///
  /// Returns null on a first install too: somebody who has never run the app
  /// does not need a list of what changed since a version they never had.
  /// Pass [freshInstall] as false for a device that has used the app before,
  /// so an update from a version that predates this dialog still shows it.
  Future<WhatsNewEntry?> pendingEntry(
    String version, {
    bool freshInstall = true,
  }) async {
    final current = _normaliseVersion(version);
    if (current.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final lastShown = prefs.getString(_lastShownKey);
    if (lastShown == current) return null;
    if (lastShown == null && freshInstall) {
      // First run we know of: record where we are and stay quiet.
      await prefs.setString(_lastShownKey, current);
      return null;
    }

    final changelog = await _loadChangelog();
    if (changelog == null) return null;
    return entrySince(changelog, current, lastSeen: lastShown);
  }

  /// Records that [version]'s notes have been seen.
  Future<void> markShown(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastShownKey, _normaliseVersion(version));
  }

  Future<String?> _loadChangelog() async {
    final cached = _cachedChangelog;
    if (cached != null) return cached;
    try {
      final text = await rootBundle.loadString(changelogAsset);
      _cachedChangelog = text;
      return text;
    } catch (_) {
      // The changelog is bundled, but a stripped build is not worth crashing.
      return null;
    }
  }
}
