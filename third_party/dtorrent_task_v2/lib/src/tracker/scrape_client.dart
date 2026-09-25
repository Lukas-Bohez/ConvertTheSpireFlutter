import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;
import '../proxy/proxy_manager.dart';

/// Logger instance for ScrapeClient
final _log = Logger('ScrapeClient');

/// Scrape statistics for a single torrent
class ScrapeStats {
  /// Number of complete peers (seeders)
  final int complete;

  /// Number of incomplete peers (leechers)
  final int incomplete;

  /// Number of peers that have downloaded the torrent
  final int downloaded;

  ScrapeStats({
    required this.complete,
    required this.incomplete,
    required this.downloaded,
  });

  @override
  String toString() {
    return 'ScrapeStats(complete: $complete, incomplete: $incomplete, downloaded: $downloaded)';
  }
}

/// Scrape result for a tracker
class ScrapeResult {
  /// Tracker URL
  final Uri trackerUrl;

  /// Statistics for each info hash (key: info hash as hex string)
  final Map<String, ScrapeStats> stats;

  /// Error message if scrape failed
  final String? error;

  /// Whether the scrape was successful
  bool get isSuccess => error == null && stats.isNotEmpty;

  ScrapeResult({
    required this.trackerUrl,
    required this.stats,
    this.error,
  });

  /// Get statistics for a specific info hash
  ScrapeStats? getStatsForInfoHash(String infoHash) {
    return stats[infoHash.toLowerCase()];
  }

  @override
  String toString() {
    if (error != null) {
      return 'ScrapeResult(tracker: $trackerUrl, error: $error)';
    }
    return 'ScrapeResult(tracker: $trackerUrl, stats: ${stats.length} torrents)';
  }
}

/// Client for performing tracker scrape requests (BEP 48)
///
/// Supports both HTTP and UDP trackers for getting torrent statistics
/// without performing a full announce.
class ScrapeClient {
  /// Cache for scrape results (key: tracker URL + info hash)
  final Map<String, ScrapeResult> _cache = {};

  /// Cache timeout (default: 5 minutes)
  final Duration cacheTimeout;

  /// Timestamps for cache entries
  final Map<String, DateTime> _cacheTimestamps = {};

  /// HTTP client timeout
  final Duration httpTimeout;

  /// UDP socket timeout
  final Duration udpTimeout;

  /// Proxy manager for HTTP requests
  final ProxyManager? proxyManager;

  ScrapeClient({
    this.cacheTimeout = const Duration(minutes: 5),
    this.httpTimeout = const Duration(seconds: 10),
    this.udpTimeout = const Duration(seconds: 5),
    this.proxyManager,
  });

  /// Perform scrape request for one or more info hashes
  ///
  /// [trackerUrl] - Tracker URL (HTTP or UDP)
  /// [infoHashes] - List of info hashes to scrape (as Uint8List)
  ///
  /// Returns [ScrapeResult] with statistics for each info hash
  Future<ScrapeResult> scrape(
    Uri trackerUrl,
    List<Uint8List> infoHashes,
  ) async {
    if (infoHashes.isEmpty) {
      return ScrapeResult(
        trackerUrl: trackerUrl,
        stats: {},
        error: 'No info hashes provided',
      );
    }

    // Check cache first
    final cacheKey = _getCacheKey(trackerUrl, infoHashes);
    final cached = _getCachedResult(cacheKey);
    if (cached != null) {
      _log.fine('Using cached scrape result for $trackerUrl');
      return cached;
    }

    try {
      ScrapeResult result;

      if (trackerUrl.scheme == 'http' || trackerUrl.scheme == 'https') {
        result = await _scrapeHttp(trackerUrl, infoHashes);
      } else if (trackerUrl.scheme == 'udp') {
        result = await _scrapeUdp(trackerUrl, infoHashes);
      } else {
        result = ScrapeResult(
          trackerUrl: trackerUrl,
          stats: {},
          error: 'Unsupported tracker scheme: ${trackerUrl.scheme}',
        );
      }

      // Cache successful results
      if (result.isSuccess) {
        _cache[cacheKey] = result;
        _cacheTimestamps[cacheKey] = DateTime.now();
      }

      return result;
    } catch (e, stackTrace) {
      _log.warning('Scrape failed for $trackerUrl', e, stackTrace);
      return ScrapeResult(
        trackerUrl: trackerUrl,
        stats: {},
        error: e.toString(),
      );
    }
  }

  /// Perform HTTP scrape request (BEP 48)
  Future<ScrapeResult> _scrapeHttp(
    Uri trackerUrl,
    List<Uint8List> infoHashes,
  ) async {
    try {
      // Build scrape URL
      // According to BEP 48: locate the string "announce" in the path and replace with "scrape"
      Uri scrapeUrl;
      final path = trackerUrl.path;
      if (path.contains('announce')) {
        // Replace "announce" with "scrape" in the path
        scrapeUrl = trackerUrl.replace(
          path: path.replaceAll('announce', 'scrape'),
        );
      } else {
        // Fallback: append /scrape if announce not found
        final basePath = path.endsWith('/') ? path : '$path/';
        scrapeUrl = trackerUrl.replace(path: '${basePath}scrape');
      }

      // Build query parameters with info hashes
      // According to BEP 48: the info_hash key can be appended multiple times
      // We need to build the query string manually to support multiple values
      final queryParts = <String>[];
      for (var infoHash in infoHashes) {
        // URL encode the info hash (binary data as per BEP 003)
        final encoded = Uri.encodeComponent(
          String.fromCharCodes(infoHash),
        );
        queryParts.add('info_hash=$encoded');
      }

      // Build final URI with query string
      final queryString = queryParts.join('&');
      final uriWithParams = scrapeUrl.replace(
        query: queryString,
      );

      _log.fine('Scraping HTTP tracker: $uriWithParams');

      // Make HTTP GET request
      final response = await http.get(
        uriWithParams,
        headers: {
          'User-Agent': 'dtorrent_task_v2/1.0',
        },
      ).timeout(httpTimeout);

      if (response.statusCode != 200) {
        return ScrapeResult(
          trackerUrl: trackerUrl,
          stats: {},
          error: 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }

      // Parse bencoded response
      final decoded = decode(response.bodyBytes);
      if (decoded is! Map) {
        return ScrapeResult(
          trackerUrl: trackerUrl,
          stats: {},
          error: 'Invalid response format: expected bencoded dictionary',
        );
      }

      // Check for failure_reason (BEP 48)
      if (decoded.containsKey('failure_reason')) {
        final failureReason = decoded['failure_reason'];
        return ScrapeResult(
          trackerUrl: trackerUrl,
          stats: {},
          error: failureReason is String
              ? failureReason
              : 'Tracker error: $failureReason',
        );
      }

      // Parse files dictionary
      final files = decoded['files'];
      if (files == null || files is! Map) {
        return ScrapeResult(
          trackerUrl: trackerUrl,
          stats: {},
          error: 'Response missing "files" dictionary',
        );
      }

      // Extract stats for each info hash
      // According to BEP 48: keys in files dict are "20-byte string representation of an infohash"
      final stats = <String, ScrapeStats>{};
      for (var infoHash in infoHashes) {
        final infoHashHex = _infoHashToHex(infoHash);

        // Try to find stats by binary info hash (20-byte string as per BEP 48)
        dynamic fileData = files[infoHash];

        // If not found, try as Uint8List key (some implementations)
        if (fileData == null) {
          for (var key in files.keys) {
            if (key is Uint8List &&
                key.length == infoHash.length &&
                _bytesEqual(key, infoHash)) {
              fileData = files[key];
              break;
            }
          }
        }

        // If still not found, try hex string (for compatibility with some trackers)
        fileData ??= files[infoHashHex];

        if (fileData != null && fileData is Map) {
          stats[infoHashHex] = ScrapeStats(
            complete: _getInt(fileData, 'complete', 0),
            incomplete: _getInt(fileData, 'incomplete', 0),
            downloaded: _getInt(fileData, 'downloaded', 0),
          );
        }
      }

      return ScrapeResult(
        trackerUrl: trackerUrl,
        stats: stats,
      );
    } catch (e, stackTrace) {
      _log.warning('HTTP scrape error for $trackerUrl', e, stackTrace);
      return ScrapeResult(
        trackerUrl: trackerUrl,
        stats: {},
        error: e.toString(),
      );
    }
  }

  /// Perform UDP scrape request (BEP 15)
  Future<ScrapeResult> _scrapeUdp(
    Uri trackerUrl,
    List<Uint8List> infoHashes,
  ) async {
    try {
      final address = await InternetAddress.lookup(
        trackerUrl.host,
        type: InternetAddressType.IPv4,
      ).timeout(udpTimeout);

      if (address.isEmpty) {
        return ScrapeResult(
          trackerUrl: trackerUrl,
          stats: {},
          error: 'Failed to resolve tracker host: ${trackerUrl.host}',
        );
      }

      final port = trackerUrl.port > 0 ? trackerUrl.port : 80;
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
      ).timeout(udpTimeout);

      try {
        // Step 1: Connect (action = 0)
        final connectionId = await _udpConnect(
          socket,
          address.first,
          port,
        );

        if (connectionId == null) {
          return ScrapeResult(
            trackerUrl: trackerUrl,
            stats: {},
            error: 'Failed to establish UDP connection',
          );
        }

        // Step 2: Scrape (action = 2)
        final stats = await _udpScrape(
          socket,
          address.first,
          port,
          connectionId,
          infoHashes,
        );

        return ScrapeResult(
          trackerUrl: trackerUrl,
          stats: stats,
        );
      } finally {
        socket.close();
      }
    } catch (e, stackTrace) {
      _log.warning('UDP scrape error for $trackerUrl', e, stackTrace);
      return ScrapeResult(
        trackerUrl: trackerUrl,
        stats: {},
        error: e.toString(),
      );
    }
  }

  /// Establish UDP connection (BEP 15)
  Future<BigInt?> _udpConnect(
    RawDatagramSocket socket,
    InternetAddress address,
    int port,
  ) async {
    final transactionId = _generateTransactionId();
    final request = ByteData(16);
    // Protocol ID (magic number) - 0x41727101980
    final protocolId = BigInt.from(0x41727101980);
    request.setUint64(0, protocolId.toInt(), Endian.big);
    // Action: 0 = connect
    request.setUint32(8, 0, Endian.big);
    // Transaction ID
    request.setUint32(12, transactionId, Endian.big);

    socket.send(request.buffer.asUint8List(), address, port);

    // Wait for response
    final completer = Completer<BigInt?>();
    Timer? timeoutTimer;
    StreamSubscription<RawSocketEvent>? subscription;

    subscription = socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram == null || datagram.data.length < 16) return;

        final response = ByteData.sublistView(datagram.data);
        final action = response.getUint32(0, Endian.big);
        final transId = response.getUint32(4, Endian.big);

        if (action == 0 && transId == transactionId) {
          timeoutTimer?.cancel();
          subscription?.cancel();
          final connectionIdInt = response.getUint64(8, Endian.big);
          final connectionId = BigInt.from(connectionIdInt);
          completer.complete(connectionId);
        }
      }
    });

    timeoutTimer = Timer(udpTimeout, () {
      subscription?.cancel();
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });

    return completer.future;
  }

  /// Perform UDP scrape (BEP 15)
  Future<Map<String, ScrapeStats>> _udpScrape(
    RawDatagramSocket socket,
    InternetAddress address,
    int port,
    BigInt connectionId,
    List<Uint8List> infoHashes,
  ) async {
    final transactionId = _generateTransactionId();
    final requestLength = 16 + (infoHashes.length * 20);
    final request = ByteData(requestLength);

    // Connection ID
    request.setUint64(0, connectionId.toInt(), Endian.big);
    // Action: 2 = scrape
    request.setUint32(8, 2, Endian.big);
    // Transaction ID
    request.setUint32(12, transactionId, Endian.big);

    // Info hashes (20 bytes each)
    var offset = 16;
    for (var infoHash in infoHashes) {
      final hashLength = infoHash.length > 20 ? 20 : infoHash.length;
      request.buffer.asUint8List().setRange(
          offset, offset + hashLength, infoHash.sublist(0, hashLength));
      offset += 20;
    }

    socket.send(request.buffer.asUint8List(), address, port);

    // Wait for response
    final completer = Completer<Map<String, ScrapeStats>>();
    Timer? timeoutTimer;
    StreamSubscription<RawSocketEvent>? subscription;

    subscription = socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram == null || datagram.data.length < 8) return;

        final response = ByteData.sublistView(datagram.data);
        final action = response.getUint32(0, Endian.big);
        final transId = response.getUint32(4, Endian.big);

        if (action == 2 && transId == transactionId) {
          timeoutTimer?.cancel();
          subscription?.cancel();

          // Parse scrape data
          final stats = <String, ScrapeStats>{};
          var offset = 8;

          for (var i = 0; i < infoHashes.length; i++) {
            if (offset + 12 > datagram.data.length) break;

            final complete = response.getUint32(offset, Endian.big);
            final downloaded = response.getUint32(offset + 4, Endian.big);
            final incomplete = response.getUint32(offset + 8, Endian.big);

            final infoHashHex = _infoHashToHex(infoHashes[i]);
            stats[infoHashHex] = ScrapeStats(
              complete: complete,
              incomplete: incomplete,
              downloaded: downloaded,
            );

            offset += 12;
          }

          completer.complete(stats);
        }
      }
    });

    timeoutTimer = Timer(udpTimeout, () {
      subscription?.cancel();
      if (!completer.isCompleted) {
        completer.complete({});
      }
    });

    return completer.future;
  }

  /// Generate random transaction ID
  int _generateTransactionId() {
    return DateTime.now().millisecondsSinceEpoch & 0xFFFFFFFF;
  }

  /// Convert info hash to hex string
  String _infoHashToHex(Uint8List infoHash) {
    return infoHash
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toLowerCase();
  }

  /// Get integer value from map with default
  int _getInt(Map map, String key, int defaultValue) {
    final value = map[key];
    if (value is int) return value;
    if (value is BigInt) return value.toInt();
    return defaultValue;
  }

  /// Compare two byte arrays for equality
  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Get cache key for tracker URL and info hashes
  String _getCacheKey(Uri trackerUrl, List<Uint8List> infoHashes) {
    final hashes = infoHashes.map(_infoHashToHex).join(',');
    return '${trackerUrl.toString()}:$hashes';
  }

  /// Get cached result if available and not expired
  ScrapeResult? _getCachedResult(String cacheKey) {
    final timestamp = _cacheTimestamps[cacheKey];
    if (timestamp == null) return null;

    final age = DateTime.now().difference(timestamp);
    if (age > cacheTimeout) {
      _cache.remove(cacheKey);
      _cacheTimestamps.remove(cacheKey);
      return null;
    }

    return _cache[cacheKey];
  }

  /// Clear all cached results
  void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
  }

  /// Clear expired cache entries
  void clearExpiredCache() {
    final now = DateTime.now();
    final keysToRemove = <String>[];

    for (var entry in _cacheTimestamps.entries) {
      final age = now.difference(entry.value);
      if (age > cacheTimeout) {
        keysToRemove.add(entry.key);
      }
    }

    for (var key in keysToRemove) {
      _cache.remove(key);
      _cacheTimestamps.remove(key);
    }
  }
}
