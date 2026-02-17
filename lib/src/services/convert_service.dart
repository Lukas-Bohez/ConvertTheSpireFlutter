import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';
import 'platform_dirs.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:uuid/uuid.dart';

import '../models/convert_result.dart';
import 'ffmpeg_service.dart';

class ConvertService {
  final FfmpegService ffmpeg;

  ConvertService({required this.ffmpeg});

  Future<ConvertResult> convertFile(File input, String target, {required String? ffmpegPath}) async {
    final targetLower = target.toLowerCase().replaceAll('.', '');
    final inputBytes = Uint8List.fromList(await input.readAsBytes());
    final inputName = _sanitizeFileName(input.uri.pathSegments.last);
    final baseName = _stripExtension(inputName);

    if (targetLower == 'zip' || targetLower == 'cbz') {
      return _zipBytes(inputBytes, '$baseName.$targetLower', inputName);
    }

    if (targetLower == 'epub') {
      final text = _decodeText(inputBytes);
      if (text == null || text.isEmpty) {
        return _report(inputName, 'epub', 'No text content available');
      }
      return _buildEpub(text, baseName);
    }

    if (_isImageTarget(targetLower)) {
      return _convertImage(inputBytes, targetLower, baseName);
    }

    if (_isMediaTarget(targetLower)) {
      return _convertMedia(input, targetLower, baseName, ffmpegPath: ffmpegPath);
    }

    if (targetLower == 'txt') {
      final text = _decodeText(inputBytes);
      if (text == null || text.isEmpty) {
        return _report(inputName, 'txt', 'Text extraction failed');
      }
      return ConvertResult(
        name: '$baseName.txt',
        mime: 'text/plain',
        bytes: text.codeUnits,
        message: 'Text extracted',
      );
    }

    if (targetLower == 'pdf') {
      return _convertToPdf(inputBytes, inputName, baseName);
    }

    return _report(inputName, targetLower, 'Unsupported target format');
  }

  bool _isImageTarget(String target) {
    return <String>{'jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif', 'tiff', 'tif'}.contains(target);
  }

  bool _isMediaTarget(String target) {
    return <String>{
      'mp3',
      'm4a',
      'mp4',
      'avi',
      'mov',
      'mkv',
      'wmv',
      'webm',
    }.contains(target);
  }

  ConvertResult _zipBytes(List<int> inputBytes, String outputName, String originalName) {
    final archive = Archive();
    archive.addFile(ArchiveFile(originalName, inputBytes.length, inputBytes));
    final encoded = ZipEncoder().encode(archive) ?? <int>[];
    return ConvertResult(
      name: outputName,
      mime: 'application/zip',
      bytes: encoded,
      message: 'Archived to zip',
    );
  }

  ConvertResult _convertImage(Uint8List inputBytes, String target, String baseName) {
    final image = img.decodeImage(inputBytes);
    if (image == null) {
      return _report(baseName, target, 'Image decode failed');
    }

    List<int> out;
    switch (target) {
      case 'jpg':
      case 'jpeg':
        out = img.encodeJpg(image);
        break;
      case 'png':
        out = img.encodePng(image);
        break;
      case 'webp':
        // WebP encoding is not available in image package 4.3.0
        // Falling back to PNG format
        out = img.encodePng(image);
        return ConvertResult(
          name: '$baseName.png',
          mime: 'image/png',
          bytes: out,
          message: 'WebP not supported; saved as PNG',
        );
      case 'bmp':
        out = img.encodeBmp(image);
        break;
      case 'gif':
        out = img.encodeGif(image);
        break;
      case 'tif':
      case 'tiff':
        out = img.encodeTiff(image);
        break;
      default:
        return _report(baseName, target, 'Unsupported image format');
    }

    return ConvertResult(
      name: '$baseName.$target',
      mime: lookupMimeType('$baseName.$target') ?? 'application/octet-stream',
      bytes: out,
      message: 'Image converted',
    );
  }

  Future<ConvertResult> _convertMedia(File input, String target, String baseName, {required String? ffmpegPath}) async {
    if (kIsWeb) {
      return _report(baseName, target, 'Media conversion is not supported on web. Use the desktop or mobile app.');
    }
    final tempDir = await PlatformDirs.getCacheDir();
    final outputPath = '${tempDir.path}${Platform.pathSeparator}$baseName.$target';

    await ffmpeg.run(
      <String>[
        '-y',
        '-i', input.path,
        if (<String>{'mp3', 'm4a'}.contains(target)) '-vn',
        outputPath,
      ],
      ffmpegPath: ffmpegPath,
    );

    final outputBytes = await File(outputPath).readAsBytes();
    await _safeDelete(outputPath);

    return ConvertResult(
      name: '$baseName.$target',
      mime: lookupMimeType('$baseName.$target') ?? 'application/octet-stream',
      bytes: outputBytes,
      message: 'Media converted',
    );
  }

  Future<ConvertResult> _convertToPdf(Uint8List inputBytes, String inputName, String baseName) async {
    final doc = pw.Document();
    final image = img.decodeImage(inputBytes);
    if (image != null) {
      final mem = img.encodeJpg(image);
      final imageProvider = pw.MemoryImage(mem);
      doc.addPage(
        pw.Page(
          build: (context) => pw.Center(child: pw.Image(imageProvider)),
        ),
      );
    } else {
      final text = _decodeText(inputBytes) ?? _buildReport(inputName, 'pdf', 'Unsupported input for PDF');
      doc.addPage(
        pw.Page(
          build: (context) => pw.Text(text),
        ),
      );
    }

    final bytes = await doc.save();
    return ConvertResult(
      name: '$baseName.pdf',
      mime: 'application/pdf',
      bytes: bytes,
      message: 'PDF generated',
    );
  }

  ConvertResult _buildEpub(String text, String baseName) {
    final bookId = const Uuid().v4();
    final safeTitle = baseName.isEmpty ? 'Document' : baseName;
    final containerXml =
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
        '  <rootfiles>\n'
        '    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>\n'
        '  </rootfiles>\n'
        '</container>\n';

    final contentOpf =
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="2.0">\n'
        '  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n'
        '    <dc:title>$safeTitle</dc:title>\n'
        '    <dc:language>en</dc:language>\n'
        '    <dc:identifier id="bookid">urn:uuid:$bookId</dc:identifier>\n'
        '  </metadata>\n'
        '  <manifest>\n'
        '    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>\n'
        '  </manifest>\n'
        '  <spine>\n'
        '    <itemref idref="chapter1"/>\n'
        '  </spine>\n'
        '</package>\n';

    final escaped = text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    final chapterXhtml =
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE html>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml">\n'
        '<head>\n'
        '  <title>$safeTitle</title>\n'
        '  <meta charset="utf-8"/>\n'
        '</head>\n'
        '<body>\n'
        '  <h1>$safeTitle</h1>\n'
        '  <pre>$escaped</pre>\n'
        '</body>\n'
        '</html>\n';

    final archive = Archive();
    final mimeBytes = utf8.encode('application/epub+zip');
    final containerBytes = utf8.encode(containerXml);
    final opfBytes = utf8.encode(contentOpf);
    final chapterBytes = utf8.encode(chapterXhtml);
    archive.addFile(ArchiveFile('mimetype', mimeBytes.length, mimeBytes));
    archive.addFile(ArchiveFile('META-INF/container.xml', containerBytes.length, containerBytes));
    archive.addFile(ArchiveFile('OEBPS/content.opf', opfBytes.length, opfBytes));
    archive.addFile(ArchiveFile('OEBPS/chapter1.xhtml', chapterBytes.length, chapterBytes));

    final bytes = ZipEncoder().encode(archive) ?? <int>[];
    return ConvertResult(
      name: '$baseName.epub',
      mime: 'application/epub+zip',
      bytes: bytes,
      message: 'EPUB generated',
    );
  }

  ConvertResult _report(String inputName, String target, String reason) {
    final report = _buildReport(inputName, target, reason);
    final bytes = report.codeUnits;
    return ConvertResult(
      name: '${_stripExtension(inputName)}.txt',
      mime: 'text/plain',
      bytes: bytes,
      message: reason,
    );
  }

  String _buildReport(String inputName, String target, String reason) {
    return 'Conversion report\n'
        'Input file: $inputName\n'
        'Target format: $target\n'
        'Reason: $reason\n';
  }

  String? _decodeText(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  String _sanitizeFileName(String value) {
    // Remove only filesystem-unsafe characters but keep Unicode (Japanese, etc.)
    final unsafe = RegExp(r'[<>:"/\\|?*]');
    String result = value.replaceAll(unsafe, '_');
    // Also replace control characters
    result = result.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '_');
    // Trim whitespace and dots from ends (Windows doesn't like trailing dots)
    result = result.trim().replaceAll(RegExp(r'\.+$'), '');
    return result.isEmpty ? 'file' : result;
  }

  String _stripExtension(String value) {
    final index = value.lastIndexOf('.');
    if (index <= 0) {
      return value;
    }
    return value.substring(0, index);
  }

  Future<void> _safeDelete(String path) async {
    if (kIsWeb) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
