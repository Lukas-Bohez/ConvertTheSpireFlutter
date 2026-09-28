import 'package:convert_the_spire_reborn/src/data/browser_db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Browser history was never trimmed; it now is, once per start.
void main() {
  late Database db;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE history (id INTEGER PRIMARY KEY '
        'AUTOINCREMENT, url TEXT NOT NULL, title TEXT, favicon TEXT, '
        'visited_at INTEGER NOT NULL)');
  });
  tearDown(() => db.close());

  Future<void> visit(String url, DateTime at) => db.insert('history',
      {'url': url, 'visited_at': at.millisecondsSinceEpoch});

  Future<List<String>> urls() async => [
        for (final row in await db.query('history', orderBy: 'visited_at'))
          row['url']! as String,
      ];

  test('drops visits older than a year', () async {
    final now = DateTime.now();
    await visit('old', now.subtract(const Duration(days: 400)));
    await visit('recent', now.subtract(const Duration(days: 10)));

    await BrowserDb.pruneHistory(db);

    expect(await urls(), ['recent']);
  });

  test('keeps only the newest entries', () async {
    final now = DateTime.now();
    for (var i = 0; i < 8; i++) {
      await visit('site$i', now.subtract(Duration(minutes: 10 - i)));
    }

    await BrowserDb.pruneHistory(db, maxRows: 3);

    expect(await urls(), ['site5', 'site6', 'site7']);
  });
}
