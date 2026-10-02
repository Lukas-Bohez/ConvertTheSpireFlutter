import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:convert_the_spire_reborn/src/services/convert_service.dart';
import 'package:convert_the_spire_reborn/src/services/ffmpeg_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Every format the Convert page offers, from the kinds of file it takes,
/// with a real FFmpeg (skipped where there is none).
void main() {
  final hasFfmpeg = _runs('ffmpeg', ['-version']);
  final skip = hasFfmpeg ? false : 'FFmpeg is not installed';
  final service = ConvertService(ffmpeg: FfmpegService());
  late Directory dir;
  late Map<String, File> inputs;

  setUpAll(() async {
    if (!hasFfmpeg) return;
    dir = await Directory.systemTemp.createTemp('convert_formats');
    String path(String name) => p.join(dir.path, name);
    Future<void> ff(List<String> args) async {
      final r = await Process.run('ffmpeg', ['-y', '-loglevel', 'error', ...args]);
      if (r.exitCode != 0) throw StateError('ffmpeg ${args.join(' ')}: ${r.stderr}');
    }

    await ff(['-f', 'lavfi', '-i', 'testsrc=size=64x48:duration=1', '-frames:v', '1', path('cover.png')]);
    await ff(['-f', 'lavfi', '-i', 'sine=frequency=440:duration=2', path('tone.mp3')]);
    // An MP3 with cover art, as downloads have.
    await ff(['-i', path('tone.mp3'), '-i', path('cover.png'), '-map', '0:a',
      '-map', '1:v', '-c:a', 'copy', '-c:v', 'mjpeg',
      '-disposition:v', 'attached_pic', path('cover.mp3')]);
    await ff(['-f', 'lavfi', '-i', 'testsrc=size=160x120:rate=15:duration=2',
      '-f', 'lavfi', '-i', 'sine=frequency=330:duration=2', '-shortest',
      '-pix_fmt', 'yuv420p', path('clip.mp4')]);
    await ff(['-i', path('cover.png'), path('photo.jpg')]);
    await File(path('notes.txt')).writeAsString('Line one\nLine two – ünïcödé\n');
    await File(path('page.html'))
        .writeAsString('<html><body><h1>Title</h1><p>Some text</p></body></html>');
    final pdf = await service.convertFile(File(path('notes.txt')), 'pdf',
        ffmpegPath: null);
    await File(path('notes.pdf')).writeAsBytes(pdf.bytes);

    inputs = {
      for (final name in [
        'tone.mp3', 'cover.mp3', 'clip.mp4', 'cover.png', 'photo.jpg',
        'notes.txt', 'page.html', 'notes.pdf',
      ])
        name: File(path(name)),
    };
  });

  tearDownAll(() async {
    if (hasFfmpeg) await dir.delete(recursive: true);
  });

  const audio = ['mp3', 'm4a', 'wav', 'flac', 'ogg', 'aac', 'wma'];
  const video = ['mp4', 'webm', 'mkv', 'avi', 'mov', 'wmv'];
  const images = ['png', 'jpg', 'bmp', 'gif', 'tiff', 'webp'];

  final cases = <String, List<String>>{
    'tone.mp3': [...audio, ...video],
    'cover.mp3': [...audio, ...video],
    'clip.mp4': [...audio, ...video],
    'cover.png': [...images, 'pdf', 'zip', 'cbz'],
    'photo.jpg': [...images, 'pdf'],
    'notes.txt': ['txt', 'pdf', 'epub', 'zip', 'cbz'],
    'page.html': ['txt', 'pdf', 'epub'],
    'notes.pdf': ['txt', 'epub'],
  };

  for (final entry in cases.entries) {
    for (final target in entry.value) {
      test('${entry.key} -> $target', () async {
        final result = await service.convertFile(inputs[entry.key]!, target,
            ffmpegPath: null);
        expect(result.name, endsWith('.$target'), reason: result.message);
        expect(result.bytes, isNotEmpty, reason: result.message);
        final out = File(p.join(dir.path, 'out_${entry.key}_${result.name}'));
        await out.writeAsBytes(result.bytes);

        if (audio.contains(target) || video.contains(target)) {
          final streams = _probe(out.path);
          expect(streams, contains('audio'), reason: 'no audio in $target');
          if (audio.contains(target)) {
            expect(streams, isNot(contains('video')),
                reason: '$target should be sound only');
          }
          if (entry.key == 'clip.mp4' && video.contains(target)) {
            expect(streams, contains('video'), reason: 'no video in $target');
          }
        } else if (images.contains(target)) {
          final decoded = img.decodeImage(Uint8List.fromList(result.bytes));
          expect(decoded, isNotNull, reason: '$target does not decode');
          expect(decoded!.width, 64);
        } else if (target == 'pdf') {
          expect(ascii.decode(result.bytes.take(5).toList()), '%PDF-');
        } else if (target == 'txt') {
          expect(utf8.decode(result.bytes), contains(
              entry.key == 'page.html' ? 'Some text' : 'Line two'));
        } else {
          final archive = ZipDecoder().decodeBytes(result.bytes);
          expect(archive.files, isNotEmpty);
        }
      }, skip: skip);
    }
  }
}

bool _runs(String exe, List<String> args) {
  try {
    return Process.runSync(exe, args).exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// The stream types in [path] ("audio", "video"), as ffprobe sees them.
List<String> _probe(String path) {
  final r = Process.runSync('ffprobe', [
    '-v', 'error', '-show_entries', 'stream=codec_type', '-of', 'csv=p=0', path,
  ]);
  if (r.exitCode != 0) return const [];
  return LineSplitter.split(r.stdout as String)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}
