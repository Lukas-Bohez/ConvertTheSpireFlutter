import 'dart:io';

import 'package:convert_the_spire_reborn/src/services/linux_app_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('appid'));
  tearDown(() => root.delete(recursive: true));

  test('the data folder under the old id moves to the new id', () async {
    final old = Directory(p.join(root.path, oldLinuxAppId));
    await File(p.join(old.path, 'shared_preferences.json'))
        .create(recursive: true);

    await moveAppIdFolder(root.path);

    expect(old.existsSync(), isFalse);
    expect(
        File(p.join(root.path, linuxAppId, 'shared_preferences.json'))
            .existsSync(),
        isTrue);
  });

  test('a folder under the new id is never overwritten', () async {
    await Directory(p.join(root.path, oldLinuxAppId, 'a'))
        .create(recursive: true);
    await Directory(p.join(root.path, linuxAppId, 'b')).create(recursive: true);

    await moveAppIdFolder(root.path);

    expect(Directory(p.join(root.path, oldLinuxAppId)).existsSync(), isTrue);
    expect(Directory(p.join(root.path, linuxAppId, 'b')).existsSync(), isTrue);
  });

  test('the id is a valid Flathub id for the GitHub repository', () {
    // io.github.<user with "-" as "_">.<repository>
    expect(linuxAppId, 'io.github.Lukas_Bohez.ConvertTheSpireFlutter');
    final cmake = File('linux/CMakeLists.txt').readAsStringSync();
    expect(cmake, contains('set(APPLICATION_ID "$linuxAppId")'));
  });
}
