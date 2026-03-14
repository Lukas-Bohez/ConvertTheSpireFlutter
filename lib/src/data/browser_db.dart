import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite database for the browser module: history, favourites, recent sites.
class BrowserDb {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'browser.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE history (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            url        TEXT NOT NULL,
            title      TEXT,
            favicon    TEXT,
            visited_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE favourites (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            url        TEXT NOT NULL UNIQUE,
            title      TEXT,
            favicon    TEXT,
            folder     TEXT DEFAULT 'Uncategorised',
            sort_order INTEGER DEFAULT 0,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE recent_sites (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            url         TEXT NOT NULL UNIQUE,
            title       TEXT,
            favicon     TEXT,
            visit_count INTEGER DEFAULT 1,
            last_visit  INTEGER NOT NULL
          )
        ''');
        // Create indexes to speed up pruning and lookups.
        await db.execute('CREATE INDEX IF NOT EXISTS idx_history_visited_at ON history(visited_at)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_history_url ON history(url)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Ensure indexes exist when upgrading from older DB versions.
        try {
          await db.execute('CREATE INDEX IF NOT EXISTS idx_history_visited_at ON history(visited_at)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_history_url ON history(url)');
        } catch (e) {
          if (kDebugMode) debugPrint('BrowserDb.onUpgrade: $e');
        }
      },
    );
    return _db!;
  }

  /// Close the underlying database if open. Safe to call multiple times.
  static Future<void> close() async {
    try {
      final db = _db;
      if (db != null) {
        await db.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('BrowserDb.close() failed: $e');
    } finally {
      _db = null;
    }
  }
}

/// Repository that exposes browser data operations backed by [BrowserDb].
class BrowserRepository extends ChangeNotifier {
  // ── History ──

  Future<void> addHistory(String url, String? title, String? favicon) async {
    final db = await BrowserDb.database;
    await db.insert('history', {
      'url': url,
      'title': title,
      'favicon': favicon,
      'visited_at': DateTime.now().millisecondsSinceEpoch,
    });
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getHistory({
    int limit = 50,
    int offset = 0,
    String? search,
  }) async {
    final db = await BrowserDb.database;
    if (search != null && search.isNotEmpty) {
      final pattern = '%$search%';
      return db.query(
        'history',
        where: 'title LIKE ? OR url LIKE ?',
        whereArgs: [pattern, pattern],
        orderBy: 'visited_at DESC',
        limit: limit,
        offset: offset,
      );
    }
    return db.query(
      'history',
      orderBy: 'visited_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  Future<void> clearHistory() async {
    final db = await BrowserDb.database;
    await db.delete('history');
    notifyListeners();
  }

  /// Prune browser history.
  /// - Removes entries older than [maxAgeDays].
  /// - Ensures at most [maxRows] rows remain by deleting oldest entries.
  Future<void> pruneHistory({int maxAgeDays = 365, int maxRows = 5000}) async {
    final db = await BrowserDb.database;
    final cutoff = DateTime.now().subtract(Duration(days: maxAgeDays)).millisecondsSinceEpoch;
    await db.delete('history', where: 'visited_at < ?', whereArgs: [cutoff]);

    final countRow = await db.rawQuery('SELECT COUNT(*) as c FROM history');
    final count = Sqflite.firstIntValue(countRow) ?? 0;
    if (count > maxRows) {
      final toDelete = count - maxRows;
      await db.rawDelete('DELETE FROM history WHERE id IN (SELECT id FROM history ORDER BY visited_at ASC LIMIT ?)', [toDelete]);
    }
    notifyListeners();
  }

  Future<void> deleteHistoryItem(int id) async {
    final db = await BrowserDb.database;
    await db.delete('history', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  // ── Favourites ──

  Future<void> addFavourite(
    String url,
    String? title,
    String? favicon, {
    String folder = 'Uncategorised',
  }) async {
    final db = await BrowserDb.database;
    await db.insert(
      'favourites',
      {
        'url': url,
        'title': title,
        'favicon': favicon,
        'folder': folder,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<void> removeFavourite(String url) async {
    final db = await BrowserDb.database;
    await db.delete('favourites', where: 'url = ?', whereArgs: [url]);
    notifyListeners();
  }

  Future<bool> isFavourite(String url) async {
    final db = await BrowserDb.database;
    final rows = await db.query('favourites',
        where: 'url = ?', whereArgs: [url], limit: 1);
    return rows.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> getFavourites({String? folder}) async {
    final db = await BrowserDb.database;
    if (folder != null) {
      return db.query('favourites',
          where: 'folder = ?',
          whereArgs: [folder],
          orderBy: 'sort_order ASC, created_at DESC');
    }
    return db.query('favourites', orderBy: 'sort_order ASC, created_at DESC');
  }

  Future<List<String>> getFolders() async {
    final db = await BrowserDb.database;
    final rows = await db.rawQuery(
        'SELECT DISTINCT folder FROM favourites ORDER BY folder');
    return rows.map((r) => r['folder'] as String).toList();
  }

  Future<void> reorderFavourites(List<int> ids) async {
    final db = await BrowserDb.database;
    final batch = db.batch();
    for (var i = 0; i < ids.length; i++) {
      batch.update('favourites', {'sort_order': i},
          where: 'id = ?', whereArgs: [ids[i]]);
    }
    await batch.commit(noResult: true);
    notifyListeners();
  }

  Future<void> updateFavourite(int id,
      {String? title, String? url, String? folder}) async {
    final db = await BrowserDb.database;
    final updates = <String, dynamic>{};
    if (title != null) updates['title'] = title;
    if (url != null) updates['url'] = url;
    if (folder != null) updates['folder'] = folder;
    if (updates.isNotEmpty) {
      await db.update('favourites', updates,
          where: 'id = ?', whereArgs: [id]);
      notifyListeners();
    }
  }

  // ── Recent Sites (Quick Access) ──

  Future<List<Map<String, dynamic>>> getRecentSites({int limit = 8}) async {
    final db = await BrowserDb.database;
    return db.query('recent_sites',
        orderBy: 'last_visit DESC', limit: limit);
  }

  Future<void> upsertRecentSite(
      String url, String? title, String? favicon) async {
    final db = await BrowserDb.database;
    final existing = await db.query('recent_sites',
        where: 'url = ?', whereArgs: [url], limit: 1);
    if (existing.isNotEmpty) {
      await db.rawUpdate(
        'UPDATE recent_sites SET visit_count = visit_count + 1, '
        'last_visit = ?, title = COALESCE(?, title), '
        'favicon = COALESCE(?, favicon) WHERE url = ?',
        [DateTime.now().millisecondsSinceEpoch, title, favicon, url],
      );
    } else {
      await db.insert('recent_sites', {
        'url': url,
        'title': title,
        'favicon': favicon,
        'visit_count': 1,
        'last_visit': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  Future<void> deleteRecentSite(int id) async {
    final db = await BrowserDb.database;
    await db.delete('recent_sites', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }
}
