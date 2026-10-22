import 'dart:io';

import 'package:convert_the_spire_reborn/src/services/download_naming.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Issue #45, fix 8: songs with the same title must not replace or delete
/// each other.
void main() {
  bool Function(String) takenOf(Set<String> names) =>
      (n) => names.map((e) => e.toLowerCase()).contains(n.toLowerCase());

  group('choose', () {
    test('a free name stays as it is', () {
      final c = DownloadNaming.choose(
          stem: 'Song', ext: 'mp3', taken: takenOf({}), videoId: 'aaaaaaaaaaa');
      expect(c.name, 'Song.mp3');
      expect(c.replace, isFalse);
    });

    test("another video's name gets this video's id", () {
      final c = DownloadNaming.choose(
          stem: 'Song',
          ext: 'mp3',
          taken: takenOf({'Song.mp3'}),
          videoId: 'bbbbbbbbbbb');
      expect(c.name, 'Song [bbbbbbbbbbb].mp3');
      expect(c.replace, isFalse);
    });

    test('names are compared without case', () {
      final c = DownloadNaming.choose(
          stem: 'Song',
          ext: 'mp3',
          taken: takenOf({'song.MP3'}),
          videoId: 'bbbbbbbbbbb');
      expect(c.name, 'Song [bbbbbbbbbbb].mp3');
    });

    test('the same video downloaded again replaces its own file', () {
      final plain = DownloadNaming.choose(
          stem: 'Song',
          ext: 'mp3',
          taken: takenOf({'Song.mp3'}),
          videoId: 'aaaaaaaaaaa',
          replaceableName: 'Song.mp3');
      expect(plain.name, 'Song.mp3');
      expect(plain.replace, isTrue);

      final withId = DownloadNaming.choose(
          stem: 'Song',
          ext: 'mp3',
          taken: takenOf({'Song.mp3', 'Song [bbbbbbbbbbb].mp3'}),
          videoId: 'bbbbbbbbbbb');
      expect(withId.name, 'Song [bbbbbbbbbbb].mp3');
      expect(withId.replace, isTrue);
    });

    test('without an id the copy is numbered', () {
      final c = DownloadNaming.choose(
          stem: 'Song',
          ext: 'mp3',
          taken: takenOf({'Song.mp3', 'Song (2).mp3'}));
      expect(c.name, 'Song (3).mp3');
      expect(c.replace, isFalse);
    });

    test('a part keeps its label and gets the id too', () {
      final c = DownloadNaming.choose(
          stem: 'Song (1m05s-2m30s)',
          ext: 'mp3',
          taken: takenOf({'Song (1m05s-2m30s).mp3'}),
          videoId: 'ccccccccccc');
      expect(c.name, 'Song (1m05s-2m30s) [ccccccccccc].mp3');
    });

    test('reads the id back from a name', () {
      expect(
          DownloadNaming.idFromName('Song [ccccccccccc].mp3'), 'ccccccccccc');
      expect(DownloadNaming.idFromName('Song.mp3'), isNull);
    });
  });

  group('placeLocal', () {
    late Directory root;
    late Directory folder;
    late Directory work;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('naming_test');
      folder = Directory(p.join(root.path, 'mp3'));
      work = await DownloadNaming.createWorkDir(root);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    Future<String> finished(String content) async {
      final f = File(p.join(work.path, 'out.mp3'));
      await f.writeAsString(content);
      return f.path;
    }

    test('two videos with the same title end up as two files', () async {
      final first = await DownloadNaming.placeLocal(
          source: await finished('first'),
          folder: folder,
          stem: 'Sasaki',
          ext: 'mp3',
          videoId: 'aaaaaaaaaaa');
      final second = await DownloadNaming.placeLocal(
          source: await finished('second'),
          folder: folder,
          stem: 'Sasaki',
          ext: 'mp3',
          videoId: 'bbbbbbbbbbb');
      expect(p.basename(first), 'Sasaki.mp3');
      expect(p.basename(second), 'Sasaki [bbbbbbbbbbb].mp3');
      expect(await File(first).readAsString(), 'first');
      expect(await File(second).readAsString(), 'second');
    });

    test("never touches a user's own file of the same name", () async {
      await folder.create(recursive: true);
      final own = File(p.join(folder.path, 'Sasaki.mp3'));
      await own.writeAsString('mine');
      final placed = await DownloadNaming.placeLocal(
          source: await finished('download'),
          folder: folder,
          stem: 'Sasaki',
          ext: 'mp3');
      expect(p.basename(placed), 'Sasaki (2).mp3');
      expect(await own.readAsString(), 'mine');
    });

    test('downloading the same video again replaces only its own file',
        () async {
      final first = await DownloadNaming.placeLocal(
          source: await finished('old'),
          folder: folder,
          stem: 'Sasaki',
          ext: 'mp3',
          videoId: 'aaaaaaaaaaa');
      final again = await DownloadNaming.placeLocal(
          source: await finished('new'),
          folder: folder,
          stem: 'Sasaki',
          ext: 'mp3',
          videoId: 'aaaaaaaaaaa',
          replaceablePath: first);
      expect(again, first);
      expect(await File(again).readAsString(), 'new');
      expect(folder.listSync().whereType<File>(), hasLength(1));
    });
  });
}
