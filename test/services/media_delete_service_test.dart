import 'dart:io';

import 'package:convert_the_spire_reborn/src/services/media_delete_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Issue #45, fix 12: deleting from the player on phones.
void main() {
  test('a picked-folder (SAF) link is deleted through SAF', () async {
    String? asked;
    final service = MediaDeleteService(
      isAndroid: true,
      deleteSafUri: (uri) async {
        asked = uri;
        return true;
      },
      deleteMediaUris: (_) async => fail('not a MediaStore item'),
      mediaUriForPath: (_) async => null,
    );
    const uri =
        'content://com.android.externalstorage.documents/tree/primary%3AMusic/document/primary%3AMusic%2Fsong.mp3';
    expect(await service.delete(uri), DeleteOutcome.deleted);
    expect(asked, uri);
  });

  test('a lost folder permission is told apart', () async {
    final service = MediaDeleteService(
      isAndroid: true,
      deleteSafUri: (_) async => throw PlatformException(
          code: 'DELETE_FAILED', message: 'Permission Denial: no access'),
      deleteMediaUris: (_) async => 'failed',
      mediaUriForPath: (_) async => null,
    );
    expect(await service.delete('content://x/tree/a/document/b'),
        DeleteOutcome.permissionLost);
  });

  test('MediaStore items go through MediaStore, and a no is a cancel',
      () async {
    final service = MediaDeleteService(
      isAndroid: true,
      deleteSafUri: (_) async => fail('not a SAF item'),
      deleteMediaUris: (uris) async =>
          uris.single.endsWith('/1') ? 'deleted' : 'cancelled',
      mediaUriForPath: (_) async => null,
    );
    expect(await service.delete('content://media/external/audio/media/1'),
        DeleteOutcome.deleted);
    expect(await service.delete('content://media/external/audio/media/2'),
        DeleteOutcome.cancelled);
  });

  test('a plain file is deleted, and a missing one counts as gone', () async {
    final dir = await Directory.systemTemp.createTemp('delete_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'song.mp3'));
    await file.writeAsString('x');
    final service = MediaDeleteService(isAndroid: false);
    expect(await service.delete(file.path), DeleteOutcome.deleted);
    expect(await file.exists(), isFalse);
    expect(await service.delete(file.path), DeleteOutcome.alreadyGone);
    expect(DeleteOutcome.alreadyGone.removed, isTrue);
    expect(DeleteOutcome.cancelled.removed, isFalse);
  });
}
