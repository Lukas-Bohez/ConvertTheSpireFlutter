import 'dart:io';

import 'package:mime/mime.dart';

/// The media type to serve [path] as.
///
/// Falls back to a generic binary type rather than guessing, which players
/// handle better than a wrong type.
String mediaContentTypeFor(String path) =>
    lookupMimeType(path) ?? 'application/octet-stream';

/// A resolved byte range, inclusive of both ends.
class ByteRange {
  final int start;
  final int end;
  final int fileLength;

  const ByteRange({
    required this.start,
    required this.end,
    required this.fileLength,
  });

  int get length => end - start + 1;

  /// The value for a `Content-Range` response header.
  String get contentRangeHeader => 'bytes $start-$end/$fileLength';
}

/// Parses a `Range` request header against a file of [fileLength] bytes.
///
/// Returns null when the header is absent or not a form we serve, which means
/// "send the whole file". Throws [RangeError] when the client asked for a
/// range that cannot be satisfied, so the caller can answer 416 rather than
/// trying to read past the end of the file - the previous implementation did
/// no clamping at all and would have tried.
ByteRange? parseByteRange(String? header, int fileLength) {
  if (header == null || fileLength <= 0) return null;

  final match =
      RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim().toLowerCase());
  if (match == null) return null;

  final startText = match.group(1) ?? '';
  final endText = match.group(2) ?? '';
  if (startText.isEmpty && endText.isEmpty) return null;

  int start;
  int end;
  if (startText.isEmpty) {
    // "bytes=-500" means the last 500 bytes.
    final suffixLength = int.parse(endText);
    if (suffixLength <= 0) throw RangeError('unsatisfiable range: $header');
    start = fileLength - suffixLength;
    if (start < 0) start = 0;
    end = fileLength - 1;
  } else {
    start = int.parse(startText);
    end = endText.isEmpty ? fileLength - 1 : int.parse(endText);
    if (start >= fileLength) throw RangeError('range past end: $header');
    if (end >= fileLength) end = fileLength - 1;
    if (end < start) throw RangeError('inverted range: $header');
  }

  return ByteRange(start: start, end: end, fileLength: fileLength);
}

/// Serves [file] over [request], honouring Range and HEAD.
///
/// Range support is what lets a guest or a TV seek in a stream instead of
/// waiting for the whole file (issue #7).
Future<void> serveFileWithRanges(
  HttpRequest request,
  File file, {
  required String contentType,
  Map<String, String> extraHeaders = const {},
}) async {
  if (!await file.exists()) {
    request.response
      ..statusCode = HttpStatus.notFound
      ..write('Not available');
    await request.response.close();
    return;
  }

  final length = await file.length();
  final response = request.response;
  response.headers
    ..contentType = ContentType.parse(contentType)
    ..set(HttpHeaders.acceptRangesHeader, 'bytes');
  extraHeaders.forEach(response.headers.set);

  ByteRange? range;
  try {
    range =
        parseByteRange(request.headers.value(HttpHeaders.rangeHeader), length);
  } on RangeError {
    response
      ..statusCode = HttpStatus.requestedRangeNotSatisfiable
      ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
    await response.close();
    return;
  }

  if (range != null) {
    response
      ..statusCode = HttpStatus.partialContent
      ..headers.set(HttpHeaders.contentRangeHeader, range.contentRangeHeader)
      ..headers.contentLength = range.length;
  } else {
    response.headers.contentLength = length;
  }

  if (request.method == 'HEAD') {
    await response.close();
    return;
  }

  final stream = range == null
      ? file.openRead()
      : file.openRead(range.start, range.end + 1);
  try {
    await stream.pipe(response);
  } catch (_) {
    // A player that seeks or closes mid-stream aborts the pipe; that is
    // normal, not an error worth surfacing.
    try {
      await response.close();
    } catch (_) {}
  }
}
