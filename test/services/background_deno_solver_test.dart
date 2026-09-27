import 'dart:io';

import 'package:convert_the_spire_reborn/src/services/background_deno_solver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Every start left a Deno solver temp folder behind; old ones now go.
void main() {
  late Directory temp;
  setUp(() async => temp = await Directory.systemTemp.createTemp('deno_sweep'));
  tearDown(() => temp.delete(recursive: true));

  test('removes old solver folders, keeps recent ones and anything else',
      () async {
    final old = await Directory(p.join(temp.path, 'yt_deno_OLD')).create();
    await File(p.join(old.path, 'deno_init.js')).writeAsString('x');
    final recent = await Directory(p.join(temp.path, 'yt_deno_NEW')).create();
    final other = await Directory(p.join(temp.path, 'other')).create();

    // With no minimum age every solver folder goes, nothing else does.
    await BackgroundDenoSolver.removeStaleTempDirs(
        parent: temp, olderThan: Duration.zero);
    expect(await old.exists(), isFalse);
    expect(await recent.exists(), isFalse);
    expect(await other.exists(), isTrue);

    final fresh = await Directory(p.join(temp.path, 'yt_deno_FRESH')).create();
    await BackgroundDenoSolver.removeStaleTempDirs(parent: temp);
    expect(await fresh.exists(), isTrue);
  });
}
