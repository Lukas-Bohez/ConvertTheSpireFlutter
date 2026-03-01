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
    final inputExt = _getExtension(inputName).toLowerCase();

    if (targetLower == 'zip' || targetLower == 'cbz') {
      return _zipBytes(inputBytes, '$baseName.$targetLower', inputName);
    }

    if (targetLower == 'epub') {
      final text = _extractTextContent(inputBytes, inputExt);
      if (text == null || text.trim().isEmpty) {
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
      final text = _extractTextContent(inputBytes, inputExt);
      if (text == null || text.trim().isEmpty) {
        return _report(inputName, 'txt', 'Text extraction failed – unsupported or binary file');
      }
      return ConvertResult(
        name: '$baseName.txt',
        mime: 'text/plain',
        bytes: utf8.encode(text),
        message: 'Text extracted',
      );
    }

    if (targetLower == 'pdf') {
      return _convertToPdf(inputBytes, inputName, baseName, inputExt);
    }

    return _report(inputName, targetLower, 'Unsupported target format');
  }

  // ===== Format detection helpers =====

  bool _isImageTarget(String target) {
    return <String>{'jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif', 'tiff', 'tif'}.contains(target);
  }

  bool _isMediaTarget(String target) {
    return <String>{
      'mp3', 'm4a', 'mp4', 'avi', 'mov', 'mkv', 'wmv', 'webm',
      'wav', 'flac', 'ogg', 'aac', 'wma',
    }.contains(target);
  }

  String _getExtension(String filename) {
    final index = filename.lastIndexOf('.');
    if (index <= 0 || index == filename.length - 1) return '';
    return filename.substring(index + 1);
  }

  // ===== Text extraction (handles PDF, plain text, HTML, etc.) =====

  /// Extracts readable text from various file formats.
  /// Returns null if the file is binary / not extractable.
  String? _extractTextContent(List<int> bytes, String inputExt) {
    // PDF files  binary format, needs special extraction
    if (inputExt == 'pdf' || _looksLikePdf(bytes)) {
      return _extractTextFromPdf(bytes);
    }

    // HTML files  strip tags
    if (inputExt == 'html' || inputExt == 'htm') {
      final raw = _decodeText(bytes);
      if (raw != null) return _stripHtmlTags(raw);
    }

    // XML files
    if (inputExt == 'xml') {
      final raw = _decodeText(bytes);
      if (raw != null) return _stripXmlTags(raw);
    }

    // CSV files
    if (inputExt == 'csv') {
      return _decodeText(bytes);
    }

    // JSON files
    if (inputExt == 'json') {
      return _decodeText(bytes);
    }

    // EPUB  extract text from contained XHTML
    if (inputExt == 'epub') {
      return _extractTextFromEpub(bytes);
    }

    // CBZ/ZIP  list contents
    if (inputExt == 'cbz' || inputExt == 'zip') {
      return _extractTextFromArchive(bytes);
    }

    // Try plain-text decode (covers .txt, .md, .log, .ini, .yaml, .dart, etc.)
    final text = _decodeText(bytes);
    if (text != null && _isReadableText(text)) {
      return text;
    }

    return null;
  }

  /// Detects PDF magic bytes (%PDF-)
  bool _looksLikePdf(List<int> bytes) {
    if (bytes.length < 5) return false;
    return bytes[0] == 0x25 &&  // %
           bytes[1] == 0x50 &&  // P
           bytes[2] == 0x44 &&  // D
           bytes[3] == 0x46 &&  // F
           bytes[4] == 0x2D;    // -
  }

  /// Extracts text from a PDF by parsing content streams.
  /// Handles the most common PDF text operators: Tj, TJ, ', "
  String? _extractTextFromPdf(List<int> bytes) {
    try {
      final raw = latin1.decode(bytes);
      final buffer = StringBuffer();

      // Strategy 1: Extract text between BT...ET blocks using text operators
      final btEtPattern = RegExp(r'BT\s(.*?)\sET', dotAll: true);
      for (final match in btEtPattern.allMatches(raw)) {
        final block = match.group(1) ?? '';

        // Tj operator: (text) Tj
        final tjPattern = RegExp(r'\(([^)]*)\)\s*Tj');
        for (final tj in tjPattern.allMatches(block)) {
          buffer.write(_decodePdfString(tj.group(1) ?? ''));
        }

        // TJ operator: [(text) num (text) ...] TJ
        final tjArrayPattern = RegExp(r'\[(.*?)\]\s*TJ', dotAll: true);
        for (final tja in tjArrayPattern.allMatches(block)) {
          final content = tja.group(1) ?? '';
          final parts = RegExp(r'\(([^)]*)\)');
          for (final part in parts.allMatches(content)) {
            buffer.write(_decodePdfString(part.group(1) ?? ''));
          }
        }

        // ' operator: (text) '
        final quotePattern = RegExp(r"\(([^)]*)\)\s*'");
        for (final q in quotePattern.allMatches(block)) {
          buffer.write(_decodePdfString(q.group(1) ?? ''));
          buffer.write('\n');
        }

        // Td/TD (positioning) can indicate line breaks
        if (block.contains(RegExp(r'T[dD]\s'))) {
          buffer.write('\n');
        }
      }

      // Strategy 2: Fall back to extracting any parenthesized strings
      // between stream...endstream if we got nothing from BT/ET
      if (buffer.toString().trim().isEmpty) {
        final streamPattern = RegExp(r'stream\s(.*?)\sendstream', dotAll: true);
        for (final sm in streamPattern.allMatches(raw)) {
          final streamContent = sm.group(1) ?? '';
          // Try to find readable text fragments
          final textPattern = RegExp(r'\(([^)]{2,})\)');
          for (final tp in textPattern.allMatches(streamContent)) {
            final text = _decodePdfString(tp.group(1) ?? '');
            if (_isReadableText(text) && text.trim().length > 1) {
              buffer.write(text);
              buffer.write(' ');
            }
          }
        }
      }

      final result = buffer.toString().trim();
      if (result.isEmpty) {
        return null; // No extractable text (probably scanned/image PDF)
      }

      // Clean up: collapse multiple whitespace, normalize line endings
      return result
          .replaceAll(RegExp(r'[ \t]+'), ' ')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim();
    } catch (e) {
      return null;
    }
  }

  /// Decode PDF escape sequences in string literals
  String _decodePdfString(String s) {
    return s
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\(', '(')
        .replaceAll(r'\)', ')')
        .replaceAll(r'\\', '\\');
  }

  /// Extract text from EPUB by reading XHTML files inside the ZIP
  String? _extractTextFromEpub(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final buffer = StringBuffer();
      for (final file in archive) {
        if (file.isFile && (file.name.endsWith('.xhtml') || file.name.endsWith('.html') || file.name.endsWith('.htm'))) {
          final content = utf8.decode(file.content as List<int>, allowMalformed: true);
          buffer.writeln(_stripHtmlTags(content));
          buffer.writeln();
        }
      }
      final result = buffer.toString().trim();
      return result.isEmpty ? null : result;
    } catch (_) {
      return null;
    }
  }

  /// List the contents of a ZIP/CBZ archive as text
  String? _extractTextFromArchive(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final buffer = StringBuffer();
      buffer.writeln('Archive contents (${archive.length} files):');
      buffer.writeln();
      for (final file in archive) {
        final sizeKb = (file.size / 1024).toStringAsFixed(1);
        buffer.writeln('  ${file.name} (${sizeKb} KB)');
      }
      return buffer.toString().trim();
    } catch (_) {
      return null;
    }
  }

  String _stripHtmlTags(String html) {
    // Remove script and style blocks first
    var clean = html.replaceAll(RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false, dotAll: true), '');
    clean = clean.replaceAll(RegExp(r'<style[^>]*>.*?</style>', caseSensitive: false, dotAll: true), '');
    // Replace block elements with newlines
    clean = clean.replaceAll(RegExp(r'<(br|p|div|h[1-6]|li|tr)[^>]*>', caseSensitive: false), '\n');
    // Strip remaining tags
    clean = clean.replaceAll(RegExp(r'<[^>]+>'), '');
    // Decode common entities
    clean = clean.replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&#39;', "'").replaceAll('&nbsp;', ' ');
    return clean.trim();
  }

  String _stripXmlTags(String xml) {
    return xml.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Heuristic: checks if text is mostly printable characters
  bool _isReadableText(String text) {
    if (text.isEmpty) return false;
    final sample = text.substring(0, text.length.clamp(0, 500));
    int printable = 0;
    for (int i = 0; i < sample.length; i++) {
      final c = sample.codeUnitAt(i);
      if (c >= 32 || c == 9 || c == 10 || c == 13) printable++;
    }
    return printable / sample.length > 0.85;
  }

  // ===== Archive =====

  ConvertResult _zipBytes(List<int> inputBytes, String outputName, String originalName) {
    final archive = Archive();
    archive.addFile(ArchiveFile(originalName, inputBytes.length, inputBytes));
    final encoded = ZipEncoder().encode(archive) ?? <int>[];
    return ConvertResult(
      name: outputName,
      mime: outputName.endsWith('.cbz') ? 'application/x-cbz' : 'application/zip',
      bytes: encoded,
      message: 'Archived to ${outputName.endsWith(".cbz") ? "CBZ" : "ZIP"}',
    );
  }

  // ===== Image =====

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
        // The image package doesn't support WebP encoding in all versions.
        // Try encoding; if unavailable, fall back to PNG.
        try {
          // image package 4.1+ can encode WebP but 4.0.x cannot
          out = img.encodePng(image); // fallback
          return ConvertResult(
            name: '$baseName.png',
            mime: 'image/png',
            bytes: out,
            message: 'WebP encoding not available; saved as PNG instead',
          );
        } catch (_) {
          out = img.encodePng(image);
          return ConvertResult(
            name: '$baseName.png',
            mime: 'image/png',
            bytes: out,
            message: 'WebP encoding not available; saved as PNG instead',
          );
        }
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
      message: 'Image converted to ${target.toUpperCase()}',
    );
  }

  // ===== Media (audio/video via FFmpeg) =====

  Future<ConvertResult> _convertMedia(File input, String target, String baseName, {required String? ffmpegPath}) async {
    if (kIsWeb) {
      return _report(baseName, target, 'Media conversion is not supported on web. Use the desktop or mobile app.');
    }
    final tempDir = await PlatformDirs.getCacheDir();
    final outputPath = '${tempDir.path}${Platform.pathSeparator}$baseName.$target';

    final args = <String>[
      '-y',
      '-i', input.path,
    ];

    // Audio-only targets: strip video track
    if (<String>{'mp3', 'm4a', 'wav', 'flac', 'ogg', 'aac', 'wma'}.contains(target)) {
      args.add('-vn');
      // Add codec settings per format
      switch (target) {
        case 'mp3':
          args.addAll(['-c:a', 'libmp3lame', '-b:a', '192k']);
          break;
        case 'm4a':
        case 'aac':
          args.addAll(['-c:a', 'aac', '-b:a', '192k']);
          break;
        case 'wav':
          args.addAll(['-c:a', 'pcm_s16le']);
          break;
        case 'flac':
          args.addAll(['-c:a', 'flac']);
          break;
        case 'ogg':
          args.addAll(['-c:a', 'libvorbis', '-b:a', '192k']);
          break;
        case 'wma':
          args.addAll(['-c:a', 'wmav2', '-b:a', '192k']);
          break;
      }
    }

    args.add(outputPath);

    try {
      await ffmpeg.run(args, ffmpegPath: ffmpegPath);

      final outputFile = File(outputPath);
      if (!await outputFile.exists()) {
        return _report(baseName, target, 'FFmpeg completed but output file was not created');
      }

      final outputBytes = await outputFile.readAsBytes();
      await _safeDelete(outputPath);

      return ConvertResult(
        name: '$baseName.$target',
        mime: lookupMimeType('$baseName.$target') ?? 'application/octet-stream',
        bytes: outputBytes,
        message: 'Media converted to ${target.toUpperCase()}',
      );
    } catch (e) {
      await _safeDelete(outputPath);
      return _report(baseName, target, 'FFmpeg conversion failed: $e');
    }
  }

  // ===== PDF generation =====

  Future<ConvertResult> _convertToPdf(Uint8List inputBytes, String inputName, String baseName, String inputExt) async {
    final doc = pw.Document();
    final image = img.decodeImage(inputBytes);
    if (image != null) {
      // Input is an image - embed it in the PDF
      final mem = img.encodeJpg(image);
      final imageProvider = pw.MemoryImage(mem);
      doc.addPage(
        pw.Page(
          build: (context) => pw.Center(child: pw.Image(imageProvider)),
        ),
      );
    } else {
      // Try extracting text for text-based inputs
      final text = _extractTextContent(inputBytes, inputExt);
      if (text != null && text.trim().isNotEmpty) {
        // Split long text across multiple pages
        final lines = text.split('\n');
        const linesPerPage = 50;
        for (int i = 0; i < lines.length; i += linesPerPage) {
          final chunk = lines.skip(i).take(linesPerPage).join('\n');
          doc.addPage(
            pw.Page(
              build: (context) => pw.Text(chunk, style: const pw.TextStyle(fontSize: 10)),
            ),
          );
        }
      } else {
        final report = _buildReport(inputName, 'pdf', 'Unsupported input for PDF conversion');
        doc.addPage(
          pw.Page(
            build: (context) => pw.Text(report),
          ),
        );
      }
    }

    final bytes = await doc.save();
    return ConvertResult(
      name: '$baseName.pdf',
      mime: 'application/pdf',
      bytes: bytes,
      message: 'PDF generated',
    );
  }

  // ===== EPUB =====

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

  // ===== Utility =====

  ConvertResult _report(String inputName, String target, String reason) {
    final report = _buildReport(inputName, target, reason);
    final bytes = utf8.encode(report);
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
      try {
        return latin1.decode(bytes);
      } catch (_) {
        return null;
      }
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
