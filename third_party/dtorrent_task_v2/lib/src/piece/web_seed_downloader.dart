import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

var _log = Logger('WebSeedDownloader');

/// Web seed downloader for HTTP/FTP seeding (BEP 0019)
///
/// Downloads pieces of a torrent file from HTTP/HTTPS web seed URLs.
/// Supports HTTP Range requests for downloading specific byte ranges.
class WebSeedDownloader {
  /// List of web seed URLs (ws parameter from magnet link)
  final List<Uri> webSeeds;

  /// List of acceptable source URLs (as parameter from magnet link)
  final List<Uri> acceptableSources;

  /// Total length of the torrent
  final int totalLength;

  /// Piece length
  final int pieceLength;

  /// Map of failed URLs to retry count
  final Map<Uri, int> _failedUrls = {};

  /// Maximum retry attempts per URL
  static const int _maxRetryAttempts = 3;

  /// Timeout for HTTP requests
  static const Duration _requestTimeout = Duration(seconds: 30);

  /// Create a new web seed downloader
  WebSeedDownloader({
    required this.webSeeds,
    required this.acceptableSources,
    required this.totalLength,
    required this.pieceLength,
  });

  /// Get all available URLs (web seeds + acceptable sources)
  List<Uri> get allUrls => [...webSeeds, ...acceptableSources];

  /// Check if web seeding is available
  bool get hasUrls => allUrls.isNotEmpty;

  /// Download a piece from web seed
  ///
  /// [pieceIndex] - index of the piece to download
  /// [pieceOffset] - offset of the piece in the torrent (in bytes)
  /// [pieceSize] - size of the piece (may be less than pieceLength for last piece)
  ///
  /// Returns the downloaded piece data, or null if download failed
  Future<Uint8List?> downloadPiece(
    int pieceIndex,
    int pieceOffset,
    int pieceSize,
  ) async {
    if (!hasUrls) {
      _log.fine('No web seed URLs available');
      return null;
    }

    // Early return for invalid piece size
    if (pieceSize <= 0) {
      _log.fine('Invalid piece size: $pieceSize');
      return null;
    }

    // Try each URL until one succeeds
    for (var url in allUrls) {
      // Skip URLs that have failed too many times
      if (_failedUrls[url] != null && _failedUrls[url]! >= _maxRetryAttempts) {
        _log.fine('Skipping failed URL: $url (${_failedUrls[url]} attempts)');
        continue;
      }

      try {
        final data = await _downloadPieceFromUrl(url, pieceOffset, pieceSize);
        if (data != null) {
          // Reset failure count on success
          _failedUrls.remove(url);
          _log.fine('Successfully downloaded piece $pieceIndex from $url');
          return data;
        }
      } catch (e) {
        _log.warning('Failed to download piece $pieceIndex from $url: $e');
        _failedUrls[url] = (_failedUrls[url] ?? 0) + 1;
      }
    }

    _log.warning('Failed to download piece $pieceIndex from all web seeds');
    return null;
  }

  /// Download a piece from a specific URL using HTTP Range request
  Future<Uint8List?> _downloadPieceFromUrl(
    Uri url,
    int pieceOffset,
    int pieceSize,
  ) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = _requestTimeout;

      // Calculate range: bytes=start-end (inclusive)
      final rangeStart = pieceOffset;
      final rangeEnd = pieceOffset + pieceSize - 1;

      final request = await client.getUrl(url);
      request.headers.set('Range', 'bytes=$rangeStart-$rangeEnd');
      request.headers.set('User-Agent', 'dtorrent_task_v2/1.0');

      final response = await request.close().timeout(_requestTimeout);

      // Check response status
      if (response.statusCode == 206) {
        // Partial Content - correct response for Range request
        final data = <int>[];
        await for (var chunk in response) {
          data.addAll(chunk);
        }

        if (data.length == pieceSize) {
          return Uint8List.fromList(data);
        } else {
          _log.warning(
              'Received ${data.length} bytes, expected $pieceSize bytes');
          return null;
        }
      } else if (response.statusCode == 200) {
        // Full content - server doesn't support Range requests
        // Read only the piece we need
        final data = <int>[];
        var bytesRead = 0;
        var skipBytes = pieceOffset;

        await for (var chunk in response) {
          if (skipBytes > 0) {
            if (chunk.length <= skipBytes) {
              skipBytes -= chunk.length;
              continue;
            } else {
              chunk = chunk.sublist(skipBytes);
              skipBytes = 0;
            }
          }

          if (bytesRead + chunk.length <= pieceSize) {
            data.addAll(chunk);
            bytesRead += chunk.length;
          } else {
            // Take only what we need
            final remaining = pieceSize - bytesRead;
            data.addAll(chunk.sublist(0, remaining));
            bytesRead += remaining;
            break;
          }
        }

        if (bytesRead == pieceSize) {
          return Uint8List.fromList(data);
        } else {
          _log.warning(
              'Received $bytesRead bytes, expected $pieceSize bytes (full content)');
          return null;
        }
      } else {
        _log.warning('Unexpected HTTP status ${response.statusCode} from $url');
        return null;
      }
    } catch (e) {
      _log.fine('Error downloading from $url: $e');
      rethrow;
    } finally {
      client?.close(force: true);
    }
  }

  /// Check if a URL is still available (not failed too many times)
  bool isUrlAvailable(Uri url) {
    return _failedUrls[url] == null || _failedUrls[url]! < _maxRetryAttempts;
  }

  /// Reset failure counts (useful for retry logic)
  void resetFailureCounts() {
    _failedUrls.clear();
  }

  /// Dispose resources
  void dispose() {
    _failedUrls.clear();
  }
}
