import 'dart:async';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static Database? _database;
  static String? _encryptionKey;

  /// Optionally set a SQLCipher key before opening the DB.
  static void setEncryptionKey(String key) {
    _encryptionKey = key;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;

    final dbPath = await _getDatabasePath();
    _database = await openDatabase(
      dbPath,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA journal_mode = WAL;');
        await db.rawQuery('PRAGMA busy_timeout = 5000;');
        await db.rawQuery('PRAGMA cache_size = -8000;');

        // Enable foreign keys
        await db.rawQuery('PRAGMA foreign_keys = ON');

        if (_encryptionKey != null && _encryptionKey!.isNotEmpty) {
          await db.rawQuery(
            "PRAGMA key = '${_encryptionKey!.replaceAll("'", "''")}'",
          );

          final cipherRows = await db.rawQuery('PRAGMA cipher_version;');
          final cipherVersion = cipherRows.isNotEmpty
              ? cipherRows.first.values.first?.toString() ?? ''
              : '';
          if (cipherVersion.isEmpty) {
            throw StateError('SQLCipher not loaded  -  check your dependencies!');
          }
        }
      },
      onOpen: (db) async {
        await _ensureChatMessageColumns(db);
        await _ensureDirectMessageServer(db);
      },
    );
    return _database!;
  }

  Future<String> _getDatabasePath() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    return join(documentsDirectory.path, 'vault_the_spire.db');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS torrents (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        total_size INTEGER,
        total_pieces INTEGER,
        piece_length INTEGER,
        pieces_have TEXT,
        status TEXT,
        type TEXT NOT NULL,
        vault_key TEXT,
        file_path TEXT,
        vault_link TEXT,
        magnet_link TEXT,
        bytes_down INTEGER DEFAULT 0,
        bytes_up INTEGER DEFAULT 0,
        added_at INTEGER,
        completed_at INTEGER,
        is_sequential INTEGER DEFAULT 0,
        selected_files TEXT,
        max_seed_ratio REAL,
        delete_after_ratio_reached INTEGER DEFAULT 0,
        seeders INTEGER DEFAULT 0,
        leechers INTEGER DEFAULT 0,
        reputation REAL DEFAULT 0.0
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        sender TEXT NOT NULL,
        recipient TEXT NOT NULL,
        body TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        is_sent INTEGER NOT NULL DEFAULT 0,
        protocol TEXT NOT NULL DEFAULT 'local'
      );
    ''');

    await _createChatTables(db);
    await _createDmTables(db);
  }

  Future<void> _createChatTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS servers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        icon TEXT,
        channels TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        id TEXT PRIMARY KEY,
        server_id TEXT NOT NULL,
        channel_id TEXT NOT NULL,
        author TEXT NOT NULL,
        text TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        edited_at INTEGER,
        reply_to TEXT,
        reactions TEXT,
        FOREIGN KEY(server_id) REFERENCES servers(id) ON DELETE CASCADE
      );
    ''');

    // Ensure a special DM server row exists so direct message records satisfy FK.
    await db.execute('''
      INSERT OR IGNORE INTO servers (id, name, description, icon, channels)
      VALUES ('_dm', 'Direct Messages', 'System direct message channel', '💬', '[]');
    ''');
  }

  Future<void> _createDmTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        username TEXT UNIQUE NOT NULL,
        status TEXT NOT NULL DEFAULT 'offline',
        last_seen INTEGER NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS conversations (
        id TEXT PRIMARY KEY,
        participant1_id TEXT NOT NULL,
        participant2_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY(participant1_id) REFERENCES users(id),
        FOREIGN KEY(participant2_id) REFERENCES users(id),
        UNIQUE(participant1_id, participant2_id)
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS dm_messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        is_read INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
        FOREIGN KEY(sender_id) REFERENCES users(id)
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_dm_messages_conversation_timestamp
      ON dm_messages (conversation_id, timestamp);
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        ALTER TABLE torrents ADD COLUMN max_seed_ratio REAL;
      ''');
      await db.execute('''
        ALTER TABLE torrents ADD COLUMN delete_after_ratio_reached INTEGER DEFAULT 0;
      ''');
    }

    if (oldVersion < 3) {
      if (!await _tableExists(db, 'chat_messages')) {
        await _createChatTables(db);
      } else {
        if (!await _columnExists(db, 'chat_messages', 'edited_at')) {
          await db.execute(
            'ALTER TABLE chat_messages ADD COLUMN edited_at INTEGER;',
          );
        }
        if (!await _columnExists(db, 'chat_messages', 'reply_to')) {
          await db.execute(
            'ALTER TABLE chat_messages ADD COLUMN reply_to TEXT;',
          );
        }
        if (!await _columnExists(db, 'chat_messages', 'reactions')) {
          await db.execute(
            'ALTER TABLE chat_messages ADD COLUMN reactions TEXT;',
          );
        }
      }
    }

    if (oldVersion < 4) {
      await db.execute('''
        ALTER TABLE torrents ADD COLUMN seeders INTEGER DEFAULT 0;
      ''');
      await db.execute('''
        ALTER TABLE torrents ADD COLUMN leechers INTEGER DEFAULT 0;
      ''');
      await db.execute('''
        ALTER TABLE torrents ADD COLUMN reputation REAL DEFAULT 0.0;
      ''');
    }

    if (oldVersion < 5) {
      await _createDmTables(db);
    }

    await _ensureChatMessageColumns(db);
    await _ensureTorrentColumns(db);
  }

  Future<bool> _tableExists(Database db, String table) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?;",
      [table],
    );
    return result.isNotEmpty;
  }

  Future<bool> _columnExists(Database db, String table, String column) async {
    if (!await _tableExists(db, table)) return false;
    final result = await db.rawQuery('PRAGMA table_info($table);');
    return result.any((row) => row['name'] == column);
  }

  Future<void> _ensureChatMessageColumns(Database db) async {
    if (!await _columnExists(db, 'chat_messages', 'edited_at')) {
      await db.execute(
        'ALTER TABLE chat_messages ADD COLUMN edited_at INTEGER;',
      );
    }
    if (!await _columnExists(db, 'chat_messages', 'reply_to')) {
      await db.execute('ALTER TABLE chat_messages ADD COLUMN reply_to TEXT;');
    }
    if (!await _columnExists(db, 'chat_messages', 'reactions')) {
      await db.execute('ALTER TABLE chat_messages ADD COLUMN reactions TEXT;');
    }
  }

  Future<void> _ensureTorrentColumns(Database db) async {
    if (!await _columnExists(db, 'torrents', 'seeders')) {
      await db.execute(
        'ALTER TABLE torrents ADD COLUMN seeders INTEGER DEFAULT 0;',
      );
    }
    if (!await _columnExists(db, 'torrents', 'leechers')) {
      await db.execute(
        'ALTER TABLE torrents ADD COLUMN leechers INTEGER DEFAULT 0;',
      );
    }
    if (!await _columnExists(db, 'torrents', 'reputation')) {
      await db.execute(
        'ALTER TABLE torrents ADD COLUMN reputation REAL DEFAULT 0.0;',
      );
    }
  }

  Future<void> _ensureDirectMessageServer(Database db) async {
    await db.execute('''
      INSERT OR IGNORE INTO servers (id, name, description, icon, channels)
      VALUES ('_dm', 'Direct Messages', 'System direct message channel', '💬', '[]');
    ''');
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
