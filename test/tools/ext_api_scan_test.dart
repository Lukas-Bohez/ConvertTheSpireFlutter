import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tools/ext_api_scan/scanner.dart';

/// Guards the compatibility-study scanner (issue #10). Its numbers go into a
/// research report, so what it counts has to be exactly what it says.
void main() {
  group('countNamespaces', () {
    test('chrome. and browser. count as the same API', () {
      expect(
        countNamespaces('chrome.tabs.query({}); browser.tabs.create({});'),
        {'tabs': 2},
      );
    });

    test('only real WebExtension namespaces are counted', () {
      const source = '''
        const url = "https://chrome.google.com/webstore";
        chrome.runtime.sendMessage({});
        browser.prototype.x = 1;
        chrome.madeUpThing.call();
      ''';

      expect(countNamespaces(source), {'runtime': 1});
    });

    test('a namespace inside a longer identifier is not a match', () {
      expect(
          countNamespaces('mychrome.tabs.query(); chromeTabs.x();'), isEmpty);
    });
  });

  group('scanning', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('ext_scan');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('an unpacked folder and a package are both read', () async {
      final folder = Directory(p.join(temp.path, 'folder-ext'))..createSync();
      File(p.join(folder.path, 'manifest.json')).writeAsStringSync(
          '{"manifest_version": 3, "name": "Folder", "version": "1",'
          ' "background": {"service_worker": "bg.js"},'
          ' "permissions": ["storage"]}');
      File(p.join(folder.path, 'bg.js')).writeAsStringSync(
          'chrome.storage.local.get(); chrome.tabs.query();');

      final archive = Archive()
        ..addFile(ArchiveFile.string(
            'manifest.json',
            '{"manifest_version": 2, "name": "Zipped", "version": "2",'
                ' "background": {"scripts": ["a.js"]}}'))
        ..addFile(ArchiveFile.string('a.js', 'browser.windows.create({});'));
      File(p.join(temp.path, 'zipped.xpi'))
          .writeAsBytesSync(ZipEncoder().encodeBytes(archive));
      File(p.join(temp.path, 'notes.txt')).writeAsStringSync('ignore me');

      final (scans, problems) = await scanAll(temp);

      expect(problems, isEmpty);
      expect(scans.map((s) => s.manifest.name), ['Folder', 'Zipped']);
      expect(scans[0].namespaces, {'storage': 1, 'tabs': 1});
      expect(scans[0].backgroundType, 'service_worker');
      expect(scans[1].namespaces, {'windows': 1});
      expect(scans[1].backgroundType, 'scripts');
    });

    test('a broken package is reported, not fatal', () async {
      File(p.join(temp.path, 'broken.zip')).writeAsStringSync('not a zip');

      final (scans, problems) = await scanAll(temp);

      expect(scans, isEmpty);
      expect(problems.single, startsWith('broken.zip:'));
    });

    test('the CSV quotes fields that need it and the matrix has every API',
        () async {
      final folder = Directory(p.join(temp.path, 'x'))..createSync();
      File(p.join(folder.path, 'manifest.json')).writeAsStringSync(
          '{"manifest_version": 3, "name": "Name, with comma",'
          ' "version": "1", "background": {"scripts": ["a.js"]}}');
      File(p.join(folder.path, 'a.js'))
          .writeAsStringSync('chrome.alarms.create(); chrome.storage.x;');

      final (scans, _) = await scanAll(temp);
      final csv = toCsv(scans);
      final matrix = toMarkdownMatrix(scans);

      expect(csv, contains('"Name, with comma"'));
      expect(csv, contains('Firefox-only'),
          reason: 'the Chromium preflight verdict is part of the data');
      expect(matrix, contains('| alarms | storage |'));
    });
  });
}
