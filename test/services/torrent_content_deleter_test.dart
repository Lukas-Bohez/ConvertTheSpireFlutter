import 'dart:io';

import 'package:convert_the_spire_reborn/src/vault/services/torrent_content_deleter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late String downloads;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('torrent_delete_test');
    downloads = p.join(root.path, 'Downloads');
    await Directory(downloads).create();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> write(String relative, [String content = 'x']) async {
    final file = File(p.join(downloads, relative));
    await file.parent.create(recursive: true);
    return file.writeAsString(content);
  }

  bool exists(String relative) =>
      FileSystemEntity.typeSync(p.join(downloads, relative)) !=
      FileSystemEntityType.notFound;

  test('deletes a single-file torrent and nothing else in the folder',
      () async {
    await write('movie.mkv');
    await write('my own notes.txt');
    await write('other torrent/episode 1.mkv');
    await write('photos/holiday.jpg');

    final result = await TorrentContentDeleter.delete(
      saveDir: downloads,
      relativeFiles: ['movie.mkv'],
    );

    expect(result.deleted, [p.join(downloads, 'movie.mkv')]);
    expect(exists('movie.mkv'), isFalse);
    expect(exists('my own notes.txt'), isTrue);
    expect(exists('other torrent/episode 1.mkv'), isTrue);
    expect(exists('photos/holiday.jpg'), isTrue);
    expect(Directory(downloads).existsSync(), isTrue);
  });

  test('deletes a multi-file torrent and the folders it leaves empty',
      () async {
    await write('Album/CD1/01.flac');
    await write('Album/CD1/02.flac');
    await write('Album/CD2/01.flac');
    await write('Album/cover.jpg');
    await write('keep.txt');

    final result = await TorrentContentDeleter.delete(
      saveDir: downloads,
      relativeFiles: [
        'Album/CD1/01.flac',
        'Album/CD1/02.flac',
        'Album/CD2/01.flac',
        'Album/cover.jpg',
      ],
    );

    expect(result.deleted, hasLength(4));
    expect(exists('Album'), isFalse);
    expect(exists('keep.txt'), isTrue);
    expect(Directory(downloads).existsSync(), isTrue);
  });

  test('keeps a torrent folder that has files of the user in it', () async {
    await write('Show/e01.mkv');
    await write('Show/Extras/e01.srt');
    await write('Show/Extras/my subtitles.srt');

    await TorrentContentDeleter.delete(
      saveDir: downloads,
      relativeFiles: ['Show/e01.mkv', 'Show/Extras/e01.srt'],
    );

    expect(exists('Show/e01.mkv'), isFalse);
    expect(exists('Show/Extras/e01.srt'), isFalse);
    expect(exists('Show/Extras/my subtitles.srt'), isTrue);
  });

  test('never deletes the folder itself or anything outside it', () async {
    await write('keep.txt');
    final outside = File(p.join(root.path, 'outside.txt'))
      ..writeAsStringSync('x');

    final result = await TorrentContentDeleter.delete(
      saveDir: downloads,
      relativeFiles: [
        '',
        '.',
        './',
        'a/..',
        '..',
        '../outside.txt',
        'sub/../../outside.txt',
        outside.path,
        '/etc/hosts',
        r'..\outside.txt',
      ],
    );

    expect(result.deleted, isEmpty);
    expect(result.skipped, hasLength(10));
    expect(outside.existsSync(), isTrue);
    expect(exists('keep.txt'), isTrue);
    expect(Directory(downloads).existsSync(), isTrue);
  });

  test('does not delete a folder where the torrent lists a file', () async {
    await write('Movie/inside.txt');

    final result = await TorrentContentDeleter.delete(
      saveDir: downloads,
      relativeFiles: ['Movie'],
    );

    expect(result.skipped, ['Movie']);
    expect(exists('Movie/inside.txt'), isTrue);
  });

  test('reports files that are already gone and still tidies up', () async {
    await write('Pack/a.bin');
    await Directory(p.join(downloads, 'Pack', 'empty')).create();

    final result = await TorrentContentDeleter.delete(
      saveDir: downloads,
      relativeFiles: ['Pack/a.bin', 'Pack/empty/b.bin'],
    );

    expect(result.deleted, [p.join(downloads, 'Pack', 'a.bin')]);
    expect(result.missing, [p.join(downloads, 'Pack', 'empty', 'b.bin')]);
    expect(exists('Pack'), isFalse);
  });

  test('deletes its own resume state file only', () async {
    await write('abc.bt.state');
    await write('def.bt.state');

    await TorrentContentDeleter.delete(
      saveDir: downloads,
      relativeFiles: const [],
      stateFileName: 'abc.bt.state',
    );

    expect(exists('abc.bt.state'), isFalse);
    expect(exists('def.bt.state'), isTrue);
  });

  test('does nothing without a download folder', () async {
    await write('movie.mkv');

    final result = await TorrentContentDeleter.delete(
      saveDir: '  ',
      relativeFiles: ['movie.mkv'],
    );

    expect(result.deleted, isEmpty);
    expect(exists('movie.mkv'), isTrue);
  });
}
