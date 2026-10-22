import 'dart:io';
import 'dart:typed_data';

import 'package:convert_the_spire_reborn/src/models/convert_result.dart';
import 'package:convert_the_spire_reborn/src/services/convert_service.dart';
import 'package:convert_the_spire_reborn/src/services/ffmpeg_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Issue #45, fix 5: a conversion that fails is an error, never a text file
/// named like the result, and every result is really the format asked for.
ConvertResult _r(String name, List<int> bytes) =>
    ConvertResult(name: name, mime: '', bytes: bytes, message: '');

void main() {
  group('checkOutput', () {
    test('accepts files that start like their format', () {
      const good = {
        'a.jpg': [0xFF, 0xD8, 0xFF, 0xE0],
        'a.png': [0x89, 0x50, 0x4E, 0x47, 0x0D],
        'a.pdf': [0x25, 0x50, 0x44, 0x46, 0x2D],
        'a.zip': [0x50, 0x4B, 0x03, 0x04],
        'a.mp4': [0, 0, 0, 0x20, 0x66, 0x74, 0x79, 0x70],
        'a.mp3': [1, 2, 3], // not inspected: FFmpeg writes it several ways
      };
      good.forEach((name, bytes) {
        final target = name.split('.').last;
        expect(ConvertService.checkOutput(_r(name, bytes), target), isNull,
            reason: name);
      });
    });

    test('rejects a text report posing as the result', () {
      final report = 'Conversion report\nReason: Image decode failed'.codeUnits;
      expect(ConvertService.checkOutput(_r('scan.jpg', report), 'jpg'),
          contains('not JPG'));
      expect(ConvertService.checkOutput(_r('scan.txt', report), 'jpg'),
          contains('scan.txt'));
    });

    test('rejects an empty file', () {
      expect(ConvertService.checkOutput(_r('a.png', []), 'png'),
          contains('empty'));
    });

    test('a zip of pages is fine for a PDF converted to pictures only', () {
      final zip = [0x50, 0x4B, 0x03, 0x04];
      expect(
          ConvertService.checkOutput(_r('doc.zip', zip), 'jpg',
              allowPagesZip: true),
          isNull);
      expect(ConvertService.checkOutput(_r('doc.zip', zip), 'jpg'),
          isNotNull);
    });
  });

  group('failures are errors', () {
    late Directory dir;
    final service = ConvertService(ffmpeg: FfmpegService());

    setUp(() async => dir = await Directory.systemTemp.createTemp('convert_fail'));
    tearDown(() => dir.delete(recursive: true));

    Future<File> file(String name, List<int> bytes) async {
      final f = File(p.join(dir.path, name));
      await f.writeAsBytes(Uint8List.fromList(bytes));
      return f;
    }

    test('a file that is not a picture does not become a .txt', () async {
      final f = await file('notapicture.png', 'just some text'.codeUnits);
      await expectLater(
          service.convertFile(f, 'jpg', ffmpegPath: null),
          throwsA(isA<ConvertException>()));
    });

    test('a PDF cannot become a WebP, and says so', () async {
      final f = await file('doc.pdf', '%PDF-1.4\n'.codeUnits);
      await expectLater(
          service.convertFile(f, 'webp', ffmpegPath: null),
          throwsA(isA<ConvertException>()
              .having((e) => e.message, 'message', contains('JPG'))));
    });

    test('an unknown target is an error', () async {
      final f = await file('a.txt', 'hello'.codeUnits);
      await expectLater(service.convertFile(f, 'xyz', ffmpegPath: null),
          throwsA(isA<ConvertException>()));
    });

    test('an image cannot become a PDF of nothing: binary input is refused',
        () async {
      final f = await file('data.bin', List.generate(64, (i) => i * 3 % 256));
      await expectLater(service.convertFile(f, 'pdf', ffmpegPath: null),
          throwsA(isA<ConvertException>()));
    });
  });
}
