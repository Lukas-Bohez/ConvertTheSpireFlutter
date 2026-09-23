import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:convert_the_spire_reborn/src/browser/extensions/extension_package.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Guards the extension installer (issue #10).
///
/// Packages come from users and from the internet, so the parser has to
/// reject damaged and hostile input with a clear message rather than install
/// something half-extracted, or write outside its own folder.
void main() {
  Uint8List zipOf(Map<String, String> files) {
    final archive = Archive();
    files.forEach((name, content) {
      archive.addFile(ArchiveFile.string(name, content));
    });
    return ZipEncoder().encodeBytes(archive);
  }

  Uint8List crx(int version, Uint8List zip, {int headerLength = 16}) {
    final header = BytesBuilder()
      ..add(ascii.encode('Cr24'))
      ..add((ByteData(4)..setUint32(0, version, Endian.little))
          .buffer
          .asUint8List())
      ..add((ByteData(4)..setUint32(0, headerLength, Endian.little))
          .buffer
          .asUint8List())
      ..add(List.filled(headerLength, 7))
      ..add(zip);
    return header.toBytes();
  }

  const mv3 = '{"manifest_version": 3, "name": "Test", "version": "1.0",'
      ' "background": {"service_worker": "bg.js"},'
      ' "action": {"default_popup": "popup.html"},'
      ' "options_ui": {"page": "options.html"},'
      ' "permissions": ["storage", "tabs"],'
      ' "host_permissions": ["<all_urls>"]}';

  group('package kinds', () {
    test('a CRX3 package unwraps to its zip', () {
      final zip = zipOf({'manifest.json': mv3});
      final archive = decodeExtensionPackage(crx(3, zip));

      expect(manifestFromArchive(archive).name, 'Test');
    });

    test('a CRX2 package is refused with an explanation', () {
      final zip = zipOf({'manifest.json': mv3});

      expect(
        () => decodeExtensionPackage(crx(2, zip)),
        throwsA(isA<ExtensionPackageException>()
            .having((e) => e.message, 'message', contains('CRX2'))),
      );
    });

    test('a truncated CRX is refused', () {
      final bytes = crx(3, zipOf({'manifest.json': mv3}));

      expect(() => decodeExtensionPackage(Uint8List.sublistView(bytes, 0, 10)),
          throwsA(isA<ExtensionPackageException>()));
      expect(() => decodeExtensionPackage(Uint8List.sublistView(bytes, 0, 20)),
          throwsA(isA<ExtensionPackageException>()),
          reason: 'header length points past the end');
    });

    test('a CRX with no zip after its header is refused', () {
      final bytes = crx(3, Uint8List.fromList(List.filled(64, 1)));

      expect(() => decodeExtensionPackage(bytes),
          throwsA(isA<ExtensionPackageException>()));
    });

    test('a plain zip or xpi is read directly', () {
      final archive = decodeExtensionPackage(zipOf({'manifest.json': mv3}));

      expect(manifestFromArchive(archive).manifestVersion, 3);
    });

    test('anything else is not an extension', () {
      expect(
        () => decodeExtensionPackage(Uint8List.fromList(utf8.encode('hello'))),
        throwsA(isA<ExtensionPackageException>()),
      );
    });
  });

  group('manifest location', () {
    test('found at the root', () {
      final archive = decodeExtensionPackage(zipOf({'manifest.json': mv3}));

      expect(manifestRootIn(archive), '');
    });

    test('found inside one wrapping folder, as GitHub release zips do', () {
      final archive = decodeExtensionPackage(
          zipOf({'dark-reader/manifest.json': mv3, 'dark-reader/bg.js': ''}));

      expect(manifestRootIn(archive), 'dark-reader/');
    });

    test('a package without a manifest is refused', () {
      final archive = decodeExtensionPackage(zipOf({'readme.txt': 'hi'}));

      expect(() => manifestRootIn(archive),
          throwsA(isA<ExtensionPackageException>()));
    });
  });

  group('manifest reading', () {
    test('MV3 fields', () {
      final m = ExtensionManifest.parse(mv3);

      expect(m.backgroundServiceWorker, 'bg.js');
      expect(m.popupPath, 'popup.html');
      expect(m.hasAction, isTrue);
      expect(m.optionsPath, 'options.html');
      expect(m.permissions, ['storage', 'tabs']);
      expect(m.hostPermissions, ['<all_urls>']);
    });

    test('MV2 host patterns inside permissions are split out', () {
      final m = ExtensionManifest.parse('{"manifest_version": 2, "name": "Old",'
          ' "version": "1", "permissions": ["storage", "<all_urls>",'
          ' "https://example.com/*"], "browser_action": {}}');

      expect(m.permissions, ['storage']);
      expect(m.hostPermissions, ['<all_urls>', 'https://example.com/*']);
      expect(m.hasAction, isTrue);
      expect(m.popupPath, isNull,
          reason: 'a button without a popup fires onClicked instead');
    });

    test('Firefox specifics are read', () {
      final m = ExtensionManifest.parse('{"manifest_version": 2, "name": "Fx",'
          ' "version": "1", "background": {"scripts": ["a.js"]},'
          ' "commands": {"toggle": {}},'
          ' "browser_specific_settings": {"gecko": {"id": "fx@example"},'
          ' "gecko_android": {}}}');

      expect(m.geckoId, 'fx@example');
      expect(m.declaresGeckoAndroid, isTrue);
      expect(m.usesCommandsKey, isTrue);
      expect(m.backgroundScripts, ['a.js']);
    });

    test('invalid JSON and unknown versions are refused', () {
      expect(() => ExtensionManifest.parse('{not json'),
          throwsA(isA<ExtensionPackageException>()));
      expect(() => ExtensionManifest.parse('[]'),
          throwsA(isA<ExtensionPackageException>()));
      expect(
          () => ExtensionManifest.parse(
              '{"manifest_version": 4, "name": "x", "version": "1"}'),
          throwsA(isA<ExtensionPackageException>()));
    });

    test('a localised name is recognised as a placeholder', () {
      final m = ExtensionManifest.parse('{"manifest_version": 3,'
          ' "name": "__MSG_extName__", "version": "1"}');

      expect(m.nameIsLocalised, isTrue);
    });
  });

  group('Chromium preflight', () {
    test('an MV3 Firefox build with background scripts is refused', () {
      final m = ExtensionManifest.parse('{"manifest_version": 3,'
          ' "name": "Fx", "version": "1", "background": {"scripts": ["a.js"]}}');

      expect(chromiumIncompatibility(m), contains('Firefox-only'));
    });

    test('an MV3 package declaring both backgrounds is attempted', () {
      final m = ExtensionManifest.parse('{"manifest_version": 3,'
          ' "name": "Both", "version": "1", "background":'
          ' {"scripts": ["a.js"], "service_worker": "a.js"}}');

      expect(chromiumIncompatibility(m), isNull);
    });

    test('MV2 packages are attempted, and the engine decides', () {
      final m = ExtensionManifest.parse('{"manifest_version": 2,'
          ' "name": "Old", "version": "1", "background": {"scripts": ["a.js"]}}');

      expect(chromiumIncompatibility(m), isNull);
    });
  });

  group('extraction', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('ext_extract');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('files land under the target, without the wrapping folder', () async {
      final archive = decodeExtensionPackage(zipOf({
        'wrap/manifest.json': mv3,
        'wrap/js/bg.js': 'console.log(1)',
      }));
      final target = Directory(p.join(temp.path, 'out'));

      await extractExtension(archive, target);

      expect(File(p.join(target.path, 'manifest.json')).existsSync(), isTrue);
      expect(File(p.join(target.path, 'js', 'bg.js')).readAsStringSync(),
          'console.log(1)');
    });

    test('Firefox signature files are left behind', () async {
      final archive = decodeExtensionPackage(zipOf({
        'manifest.json': mv3,
        'META-INF/mozilla.rsa': 'sig',
      }));
      final target = Directory(p.join(temp.path, 'out'));

      await extractExtension(archive, target);

      expect(Directory(p.join(target.path, 'META-INF')).existsSync(), isFalse);
    });

    test('a path escaping the target is refused and writes nothing outside',
        () async {
      final archive = Archive()
        ..addFile(ArchiveFile.string('manifest.json', mv3))
        ..addFile(ArchiveFile.string('../escaped.txt', 'owned'));
      final target = Directory(p.join(temp.path, 'out'));

      await expectLater(
        extractExtension(archive, target),
        throwsA(isA<ExtensionPackageException>()),
      );
      expect(File(p.join(temp.path, 'escaped.txt')).existsSync(), isFalse);
    });
  });
}
