import 'dart:io';

import 'package:archive/archive.dart';
import 'package:convert_the_spire_reborn/src/services/convert_service.dart';
import 'package:convert_the_spire_reborn/src/services/ffmpeg_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;

/// Issue #45, fix 5: a PDF converted to pictures, with the platform's real PDF
/// renderer. A unit test cannot do this, the renderer is native.
///
///   flutter test -d windows integration_test/pdf_to_images_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final service = ConvertService(ffmpeg: FfmpegService());
  late Directory dir;

  Future<File> makePdf(String name, int pages) async {
    final doc = pw.Document();
    for (var i = 1; i <= pages; i++) {
      doc.addPage(pw.Page(
        build: (_) => pw.Center(
            child: pw.Text('Page $i', style: const pw.TextStyle(fontSize: 40))),
      ));
    }
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(await doc.save());
    return file;
  }

  setUpAll(() async => dir = await Directory.systemTemp.createTemp('pdf_img'));
  tearDownAll(() => dir.delete(recursive: true));

  testWidgets('one page becomes one JPEG', (tester) async {
    final pdf = await makePdf('one.pdf', 1);
    final result = await service.convertFile(pdf, 'jpg', ffmpegPath: null);
    expect(result.name, 'one.jpg');
    expect(result.bytes.take(3), [0xFF, 0xD8, 0xFF]);
  });

  testWidgets('one page becomes a PNG', (tester) async {
    final pdf = await makePdf('one.pdf', 1);
    final result = await service.convertFile(pdf, 'png', ffmpegPath: null);
    expect(result.name, 'one.png');
    expect(result.bytes.take(4), [0x89, 0x50, 0x4E, 0x47]);
  });

  testWidgets('three pages become a zip of three JPEGs', (tester) async {
    final pdf = await makePdf('three.pdf', 3);
    final result = await service.convertFile(pdf, 'jpg', ffmpegPath: null);
    expect(result.name, 'three.zip');
    final files = ZipDecoder().decodeBytes(result.bytes).files;
    expect(files.map((f) => f.name),
        ['page-001.jpg', 'page-002.jpg', 'page-003.jpg']);
    for (final f in files) {
      expect((f.content as List<int>).take(3), [0xFF, 0xD8, 0xFF]);
    }
  });

  testWidgets('a damaged PDF is an error, not a text file', (tester) async {
    final bad = File(p.join(dir.path, 'bad.pdf'));
    await bad.writeAsString('%PDF-1.4 this is not a real pdf');
    await expectLater(service.convertFile(bad, 'jpg', ffmpegPath: null),
        throwsA(isA<ConvertException>()));
  });
}
