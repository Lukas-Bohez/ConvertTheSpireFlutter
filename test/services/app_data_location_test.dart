import 'dart:io';

import 'package:convert_the_spire_reborn/src/services/app_data_location.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The app's databases move from Documents to its data folder on desktop.
void main() {
  late Directory root;
  late Directory documents;
  late Directory data;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('app_data_location');
    documents = await Directory(p.join(root.path, 'Documents')).create();
    data = await Directory(p.join(root.path, 'AppData')).create();
  });
  tearDown(() => root.delete(recursive: true));

  Future<void> move(String name) =>
      AppDataLocation.moveIfThere(documents, data, name);
  File old(String name) => File(p.join(documents.path, name));
  File moved(String name) => File(p.join(data.path, name));

  test('moves a database with its -wal and -shm files', () async {
    await old('app.db').writeAsString('db');
    await old('app.db-wal').writeAsString('wal');
    await old('app.db-shm').writeAsString('shm');

    await move('app.db');

    expect(await moved('app.db').readAsString(), 'db');
    expect(await moved('app.db-wal').readAsString(), 'wal');
    expect(await moved('app.db-shm').readAsString(), 'shm');
    expect(await documents.list().isEmpty, isTrue);
  });

  test('moves a folder with what is in it', () async {
    await File(p.join(documents.path, 'sources', 'a.torrent'))
        .create(recursive: true);
    await File(p.join(documents.path, 'sources', 'b.torrent'))
        .writeAsString('b');

    await move('sources');

    expect(await File(p.join(data.path, 'sources', 'b.torrent')).readAsString(),
        'b');
    expect(await File(p.join(data.path, 'sources', 'a.torrent')).exists(),
        isTrue);
    expect(await Directory(p.join(documents.path, 'sources')).exists(),
        isFalse);
  });

  test('leaves both alone when the new place already has one', () async {
    await old('app.db').writeAsString('old');
    await moved('app.db').writeAsString('new');

    await move('app.db');

    expect(await old('app.db').readAsString(), 'old');
    expect(await moved('app.db').readAsString(), 'new');
  });

  test('does nothing when there is nothing to move', () async {
    await move('app.db');
    expect(await moved('app.db').exists(), isFalse);
  });

  test('finishes a move that was cut short', () async {
    // The -wal went, the database itself did not.
    await old('app.db').writeAsString('db');
    await moved('app.db-wal').writeAsString('wal');

    await move('app.db');

    expect(await moved('app.db').readAsString(), 'db');
    expect(await moved('app.db-wal').readAsString(), 'wal');
  });
}
