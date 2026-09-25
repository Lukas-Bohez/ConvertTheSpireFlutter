import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' show sha1;
import 'package:logging/logging.dart';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:dart_ipify/dart_ipify.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:bittorrent_dht/bittorrent_dht.dart';
import 'package:dtorrent_task_v2/src/metadata/metadata_downloader_events.dart';
import 'package:dtorrent_task_v2/src/peer/protocol/peer_events.dart';
import 'package:dtorrent_tracker/dtorrent_tracker.dart' hide PeerEvent;
import 'package:events_emitter2/events_emitter2.dart';

import '../peer/protocol/peer.dart';
import '../peer/extensions/holepunch.dart';
import '../peer/extensions/pex.dart';
import '../utils.dart';
import 'metadata_messenger.dart';
import 'magnet_parser.dart' show MagnetParser, TrackerTier;

/// Logger instance for MetadataDownloader
final _log = Logger('MetadataDownloader');

/// Downloads metadata (torrent info dictionary) using the ut_metadata extension.
///
/// Implements [BEP 0009](http://www.bittorrent.org/beps/bep_0009.html) (Metadata Exchange)
/// and integrates with PEX and DHT for peer discovery.
class MetadataDownloader
    with
        Holepunch,
        PEX,
        MetaDataMessenger,
        EventsEmittable<MetadataDownloaderEvent>
    implements AnnounceOptionsProvider {
  /// IP addresses that should be ignored for peer connections
  final List<InternetAddress> ignoreIps = [
    InternetAddress.anyIPv4,
    InternetAddress.loopbackIPv4
  ];

  /// Our external IP address as seen by peers
  InternetAddress? localExternalIP;

  /// Total size of metadata in bytes
  int? _metaDataSize;

  /// Number of metadata blocks (16KiB each, except possibly the last block)
  int? _metaDataBlockNum;

  /// Returns the total size of metadata in bytes
  int? get metaDataSize => _metaDataSize;

  /// Returns number of bytes downloaded so far
  int? get bytesDownloaded =>
      _metaDataSize != null ? _completedPieces.length * 16 * 1024 : 0;

  /// Download progress as percentage (0-100)
  double get progress => _metaDataBlockNum != null
      ? _completedPieces.length / _metaDataBlockNum! * 100
      : 0;

  /// Our peer ID for the BitTorrent protocol
  late String _localPeerId;

  /// Info hash as bytes
  late List<int> _infoHashBuffer;

  /// Info hash as hex string
  final String _infoHashString;

  /// Currently connected peers
  final Set<Peer> _activePeers = {};

  /// Peers that support metadata exchange
  final Set<Peer> _availablePeers = {};

  /// Map of peer event listeners
  final Map<Peer, EventsListener<PeerEvent>> _peerListeners = {};

  /// Set of all known peer addresses
  final Set<CompactAddress> _peersAddress = {};

  /// Set of addresses with incoming connections
  final Set<InternetAddress> _incomingAddress = {};

  /// DHT instance for peer discovery
  final DHT _dht = DHT();
  DHT get dht => _dht;

  /// Whether the downloader is currently running
  bool _running = false;

  /// End of bencoded data marker
  final int E = 'e'.codeUnits[0];

  /// Buffer for storing downloaded metadata pieces
  List<int> _metadataBuffer = [];

  /// Queue of metadata pieces to download
  final Queue<int> _metaDataPieces = Queue();

  /// List of completed piece indices
  final List<int> _completedPieces = [];

  /// Map of request timeouts by peer ID and piece index
  /// Key format: '${peerId}_$piece'
  final Map<String, Timer> _requestTimeout = {};

  /// Trackers from magnet link (if created from magnet URI)
  final List<Uri> _magnetTrackers = [];

  /// Tracker tiers from magnet link (BEP 0012)
  final List<TrackerTier> _magnetTrackerTiers = [];

  /// Whether this is a private torrent (BEP 0027)
  bool _isPrivate = false;

  /// Tracker client for announcing to trackers
  TorrentAnnounceTracker? _tracker;

  /// Tracker event listener
  EventsListener? _trackerListener;

  /// Maximum number of retry attempts for metadata download
  static const int _maxRetryAttempts = 3;

  /// Current retry attempt count
  int _retryAttempt = 0;

  /// Cache directory for metadata files
  static String? _cacheDirectory;

  /// Set cache directory for metadata files
  static void setCacheDirectory(String? directory) {
    _cacheDirectory = directory;
  }

  /// Get cache directory (defaults to system temp + metadata_cache)
  static Future<String> _getCacheDirectory() async {
    if (_cacheDirectory != null) {
      return _cacheDirectory!;
    }
    final tempDir = Directory.systemTemp;
    final cacheDir = Directory('${tempDir.path}/metadata_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir.path;
  }

  /// Load metadata from cache if available
  static Future<Uint8List?> loadFromCache(String infoHashString) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final cacheFile = File('$cacheDir/$infoHashString.torrent');
      if (await cacheFile.exists()) {
        _log.info('Loading metadata from cache: $infoHashString');
        return await cacheFile.readAsBytes();
      }
    } catch (e) {
      _log.warning('Failed to load metadata from cache', e);
    }
    return null;
  }

  /// Save metadata to cache
  Future<void> _saveToCache(Uint8List metadataBytes) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final cacheFile = File('$cacheDir/$_infoHashString.torrent');
      await cacheFile.writeAsBytes(metadataBytes);
      _log.info('Metadata saved to cache: $_infoHashString');
    } catch (e) {
      _log.warning('Failed to save metadata to cache', e);
    }
  }

  /// Creates a new metadata downloader for the given info hash
  MetadataDownloader(this._infoHashString,
      {List<Uri>? trackers, List<TrackerTier>? trackerTiers}) {
    _localPeerId = generatePeerId();
    List<int>? parsedHash;
    try {
      parsedHash = hexString2Buffer(_infoHashString);
    } on FormatException {
      parsedHash = null;
    }
    if (parsedHash == null || parsedHash.length != 20) {
      throw ArgumentError.value(
        _infoHashString,
        'infoHashString',
        'Must be a 40-character hex info hash',
      );
    }
    _infoHashBuffer = parsedHash;
    if (trackers != null) {
      _magnetTrackers.addAll(trackers);
    }
    if (trackerTiers != null) {
      _magnetTrackerTiers.addAll(trackerTiers);
      // Also populate flat list from tiers if not already set
      if (_magnetTrackers.isEmpty) {
        for (var tier in trackerTiers) {
          _magnetTrackers.addAll(tier.trackers);
        }
      }
    }
    _init();
    _log.info('Created MetadataDownloader for hash: $_infoHashString');
  }

  /// Create a metadata downloader from a magnet URI
  ///
  /// Example:
  /// ```dart
  /// var downloader = MetadataDownloader.fromMagnet('magnet:?xt=urn:btih:...');
  /// await downloader.startDownload();
  /// ```
  factory MetadataDownloader.fromMagnet(String magnetUri) {
    final magnet = MagnetParser.parse(magnetUri);
    if (magnet == null) {
      throw ArgumentError('Invalid magnet URI: $magnetUri');
    }
    return MetadataDownloader(
      magnet.infoHashString,
      trackers: magnet.trackers,
      trackerTiers: magnet.trackerTiers,
    );
  }
  Future<void> _init() async {
    try {
      localExternalIP = InternetAddress.tryParse(await Ipify.ipv4());
      _log.info('External IP detected: $localExternalIP');
    } catch (e) {
      _log.warning('Failed to detect external IP', e);
    }
  }

  Future<void> startDownload() async {
    if (_running) return;

    // Check cache first
    final cachedMetadata = await loadFromCache(_infoHashString);
    if (cachedMetadata != null) {
      final cachedHash = sha1.convert(cachedMetadata).toString();
      if (cachedHash == _infoHashString) {
        _log.info('Using cached metadata for $_infoHashString');
        events.emit(MetaDataDownloadComplete(cachedMetadata));
        return;
      }
      _log.warning(
        'Cached metadata hash mismatch for $_infoHashString. '
        'Expected $_infoHashString, got $cachedHash. Ignoring cache.',
      );
    }

    _running = true;

    // Initialize tracker client if we have trackers from magnet link
    if (_magnetTrackers.isNotEmpty) {
      _log.info('Using ${_magnetTrackers.length} trackers from magnet link');
      try {
        _tracker ??= TorrentAnnounceTracker(this);
        _trackerListener ??= _tracker!.createListener();

        // Listen for peers from tracker
        _trackerListener!.on<AnnouncePeerEventEvent>((event) {
          if (event.event != null) {
            final peers = event.event!.peers;
            _log.info('Got ${peers.length} peer(s) from tracker');
            for (var peer in peers) {
              addNewPeerAddress(peer, PeerSource.tracker);
            }
          }
        });

        // Announce to trackers from magnet link
        // Use tiers if available (BEP 0012), otherwise use flat list
        final infoHashBuffer = Uint8List.fromList(_infoHashBuffer);

        if (_magnetTrackerTiers.isNotEmpty) {
          // Announce to trackers tier by tier (try first tier, then next, etc.)
          for (var tier in _magnetTrackerTiers) {
            _log.info(
                'Announcing to tier with ${tier.trackers.length} tracker(s)');
            for (var trackerUri in tier.trackers) {
              try {
                _tracker!.runTracker(trackerUri, infoHashBuffer);
                _log.info('Announced to tracker: $trackerUri');
              } catch (e) {
                _log.warning('Failed to announce to tracker: $trackerUri', e);
              }
            }
          }
        } else {
          // Fallback to flat list
          for (var trackerUri in _magnetTrackers) {
            try {
              _tracker!.runTracker(trackerUri, infoHashBuffer);
              _log.info('Announced to tracker: $trackerUri');
            } catch (e) {
              _log.warning('Failed to announce to tracker: $trackerUri', e);
            }
          }
        }
      } catch (e) {
        _log.warning('Failed to initialize tracker client', e);
      }
    }

    // Only use DHT if not a private torrent (BEP 0027)
    // Note: We don't know if it's private yet, but we'll check during handshake
    var dhtListener = _dht.createListener();
    dhtListener.on<NewPeerEvent>(_processDHTPeer);
    var port = await _dht.bootstrap();
    if (port != null && !_isPrivate) {
      _dht.announce(String.fromCharCodes(_infoHashBuffer), port);
    } else if (_isPrivate) {
      _log.info('Skipping DHT announce for private torrent');
    }
  }

  Future stop() async {
    _running = false;
    await _dht.stop();

    // Dispose tracker
    _trackerListener?.dispose();
    _trackerListener = null;
    _tracker?.dispose();
    _tracker = null;

    var fs = <Future>[];
    for (var peer in _activePeers) {
      unHookPeer(peer);
      fs.add(peer.dispose());
    }
    _activePeers.clear();
    _availablePeers.clear();
    _peersAddress.clear();
    _incomingAddress.clear();
    _metaDataPieces.clear();
    _completedPieces.clear();
    _requestTimeout.forEach((key, value) {
      value.cancel();
    });
    _requestTimeout.clear();
    _pieceRetryCount.clear(); // Clear retry counts
    _retryAttempt = 0; // Reset retry counter
    await Stream.fromFutures(fs).toList();
  }

  void _processDHTPeer(NewPeerEvent event) {
    if (event.infoHash == String.fromCharCodes(_infoHashBuffer)) {
      addNewPeerAddress(event.address, PeerSource.dht);
    }
  }

  /// Add a new peer [address] , the default [type] is `PeerType.TCP`,
  /// [socket] is null.
  ///
  /// Usually [socket] is null , unless this peer was incoming connection, but
  /// this type peer was managed by [TorrentTask] , user don't need to know that.
  void addNewPeerAddress(CompactAddress address, PeerSource source,
      [PeerType type = PeerType.TCP, dynamic socket]) {
    if (!_running) return;
    if (address.address == localExternalIP) return;
    if (socket != null) {
      //  Indicates that it is an actively connecting peer, and currently, only
      //  one connection per IP address is allowed.
      if (!_incomingAddress.add(address.address)) {
        return;
      }
    }
    if (_peersAddress.add(address)) {
      Peer? peer;
      if (type == PeerType.TCP) {
        peer = Peer.newTCPPeer(address, _infoHashBuffer, 0, socket, source);
      }
      if (type == PeerType.UTP) {
        peer = Peer.newUTPPeer(address, _infoHashBuffer, 0, socket, source);
      }
      if (peer != null) _hookPeer(peer);
    }
  }

  void _hookPeer(Peer peer) {
    if (peer.address.address == localExternalIP) return;
    if (_peerExist(peer)) return;
    _peerListeners[peer] = peer.createListener();
    _peerListeners[peer]!
      ..on<PeerDisposeEvent>(
          (event) => _processPeerDispose(event.peer, event.reason))
      ..on<PeerHandshakeEvent>((event) =>
          _processPeerHandshake(event.peer, event.remotePeerId, event.data))
      ..on<PeerConnected>((event) => _peerConnected(event.peer))
      ..on<ExtendedEvent>((event) =>
          _processExtendedMessage(peer, event.eventName, event.data));
    _registerExtended(peer);
    peer.connect();
  }

  bool _peerExist(Peer id) {
    return _activePeers.contains(id);
  }

  /// Add supported extensions here
  void _registerExtended(Peer peer) {
    peer.registerExtend('ut_metadata');
    peer.registerExtend('ut_pex');
    peer.registerExtend('ut_holepunch');
  }

  void unHookPeer(Peer peer) {
    peer.events.dispose();
    _peerListeners.remove(peer);
  }

  void _peerConnected(Peer peer) {
    if (!_running) return;
    _activePeers.add(peer);
    peer.sendHandShake(_localPeerId);
  }

  void _processPeerDispose(Peer peer, [dynamic reason]) {
    _peerListeners.remove(peer);

    if (!_running) return;
    _peersAddress.remove(peer.address);
    _incomingAddress.remove(peer.address.address);
    _activePeers.remove(peer);
  }

  void _processPeerHandshake(dynamic source, String remotePeerId, data) {
    if (!_running) return;
  }

  void _processExtendedMessage(dynamic source, String name, dynamic data) {
    if (!_running) return;
    var peer = source as Peer;
    _log.fine('Received extended message "$name" from peer ${peer.address}');

    if (name == 'ut_metadata' && data is Uint8List) {
      _log.fine('Processing metadata message from peer ${peer.address}');
      parseMetaDataMessage(peer, data);
    }
    if (name == 'ut_holepunch') {
      parseHolepunchMessage(data);
    }
    if (name == 'ut_pex') {
      parsePEXDatas(source, data);
    }
    if (name == 'handshake') {
      // Check for private torrent flag (BEP 0027)
      if (data['private'] == 1 && !_isPrivate) {
        _isPrivate = true;
        _log.info('Private torrent detected - disabling DHT and PEX');
        // Stop DHT announce for private torrents
        _dht.stop();
        // PEX is already controlled through extension registration
        // We should not register ut_pex for private torrents, but since
        // we've already registered it, we'll just not use PEX peers
      }

      if (data['metadata_size'] != null && _metaDataSize == null) {
        _metaDataSize = data['metadata_size'];
        _log.info('Received metadata size: $_metaDataSize bytes');
        _metadataBuffer = List.filled(_metaDataSize!, 0);
        _metaDataBlockNum = _metaDataSize! ~/ (16 * 1024);
        if (_metaDataBlockNum! * (16 * 1024) != _metaDataSize) {
          _metaDataBlockNum = _metaDataBlockNum! + 1;
        }
        for (var i = 0; i < _metaDataBlockNum!; i++) {
          _metaDataPieces.add(i);
        }
      }

      if (localExternalIP != null &&
          data['yourip'] != null &&
          (data['yourip'].length == 4 || data['yourip'].length == 16)) {
        InternetAddress myIp;
        try {
          myIp = InternetAddress.fromRawAddress(data['yourip']);
        } catch (e) {
          return;
        }
        if (ignoreIps.contains(myIp)) return;
        localExternalIP = InternetAddress.fromRawAddress(data['yourip']);
      }

      var metaDataEventId = peer.getExtendedEventId('ut_metadata');
      if (metaDataEventId != null && _metaDataSize != null) {
        _availablePeers.add(peer);
        _requestMetaData(peer);
      }
    }
  }

  void parseMetaDataMessage(Peer peer, Uint8List data) {
    if (!_running || _metaDataBlockNum == null) return;
    int? index;
    var remotePeerId = peer.remotePeerId;
    try {
      for (var i = 0; i + 1 < data.length; i++) {
        if (data[i] == E && data[i + 1] == E) {
          index = i + 1;
          break;
        }
      }
      if (index == null) return;

      var msg = decode(data, start: 0, end: index + 1);
      if (msg['msg_type'] == 1) {
        // Piece message
        var piece = msg['piece'];
        if (piece != null && piece < _metaDataBlockNum!) {
          // Remove timeout using peer ID and piece index
          final timeoutKey = '${remotePeerId}_$piece';
          var timer = _requestTimeout.remove(timeoutKey);
          timer?.cancel();
          // Reset retry count on successful download
          _pieceRetryCount.remove(piece);
          _pieceDownloadComplete(piece, index + 1, data);
          _requestMetaData(peer);
        }
      }
      if (msg['msg_type'] == 2) {
        //  Reject piece
        var piece = msg['piece'];
        if (piece != null && piece < _metaDataBlockNum!) {
          _metaDataPieces.add(piece); //Return rejected piece
          // Remove timeout using peer ID and piece index
          final timeoutKey = '${remotePeerId}_$piece';
          var timer = _requestTimeout.remove(timeoutKey);
          timer?.cancel();
          _requestMetaData();
        }
      }
    } catch (e) {
      _log.fine('Ignoring malformed metadata message from ${peer.address}: $e');
    }
  }

  void _pieceDownloadComplete(int piece, int start, List<int> bytes) async {
    if (_completedPieces.length >= _metaDataBlockNum! ||
        _completedPieces.contains(piece)) {
      _log.warning('Duplicate or late piece $piece received, ignoring');
      return;
    }

    _log.info(
        'Piece $piece downloaded (${_completedPieces.length + 1}/$_metaDataBlockNum)');

    var pieceOffset = piece * 16 * 1024;
    List.copyRange(_metadataBuffer, pieceOffset, bytes, start);
    _completedPieces.add(piece);

    double currentProgress = progress;
    _log.info('Download progress: ${currentProgress.toStringAsFixed(2)}%');
    events.emit(MetaDataDownloadProgress(currentProgress));

    if (_completedPieces.length >= _metaDataBlockNum!) {
      _log.info('Metadata download complete! Verifying...');
      var digest = sha1.convert(_metadataBuffer);
      var valid = digest.toString() == _infoHashString;
      if (!valid) {
        _retryAttempt++;
        if (_retryAttempt < _maxRetryAttempts) {
          _log.warning(
              'Metadata verification failed! Hash mismatch. Retrying... (attempt $_retryAttempt/$_maxRetryAttempts)');

          // Clear state for retry
          _completedPieces.clear();
          _metadataBuffer = List.filled(_metaDataSize!, 0);
          _metaDataPieces.clear();
          for (var i = 0; i < _metaDataBlockNum!; i++) {
            _metaDataPieces.add(i);
          }

          // Cancel all pending timeouts
          _requestTimeout.forEach((key, value) {
            value.cancel();
          });
          _requestTimeout.clear();

          // Restart metadata download
          _log.info('Restarting metadata download...');
          _requestMetaData();
          return;
        } else {
          _log.severe(
              'Metadata verification failed after $_maxRetryAttempts attempts. Giving up.');
          events.emit(MetaDataDownloadFailed(
              'Metadata verification failed after $_maxRetryAttempts attempts'));
          await stop();
          return;
        }
      }
      _log.info('Metadata verified successfully');
      // Reset retry counter on success
      _retryAttempt = 0;

      // Save to cache
      final metadataBytes = Uint8List.fromList(_metadataBuffer);
      await _saveToCache(metadataBytes);

      // Emit the complete event with the downloaded metadata
      events.emit(MetaDataDownloadComplete(metadataBytes));
      await stop();
      _log.info('Metadata successfully downloaded and verified');
      return;
    }
  }

  /// Map tracking retry count for each piece
  final Map<int, int> _pieceRetryCount = {};

  void _requestMetaData([Peer? peer]) {
    if (!_running) return;
    if (_metaDataPieces.isEmpty || _availablePeers.isEmpty) return;

    // Request blocks from multiple peers in parallel
    // Use up to min(available pieces, available peers) parallel requests
    final availablePeersList = _availablePeers.toList();
    final maxParallelRequests =
        _metaDataPieces.length < availablePeersList.length
            ? _metaDataPieces.length
            : availablePeersList.length;

    for (var i = 0;
        i < maxParallelRequests && _metaDataPieces.isNotEmpty;
        i++) {
      final targetPeer = availablePeersList[i % availablePeersList.length];
      if (targetPeer.remotePeerId == null) continue;

      final piece = _metaDataPieces.removeFirst();
      final msg = createRequestMessage(piece);

      // Create timeout key with both peer ID and piece index
      final timeoutKey = '${targetPeer.remotePeerId}_$piece';

      // Exponential backoff: base timeout 10s, +5s per retry (max 30s)
      final retryCount = _pieceRetryCount[piece] ?? 0;
      final timeoutSeconds = 10 + (retryCount * 5);
      final timeoutDuration =
          Duration(seconds: timeoutSeconds > 30 ? 30 : timeoutSeconds);

      var timer = Timer(timeoutDuration, () {
        if (!_running) {
          _requestTimeout.remove(timeoutKey);
          return;
        }
        // On timeout, increment retry count and return piece to queue
        _pieceRetryCount[piece] = retryCount + 1;

        // If piece failed too many times, log warning but still retry
        if (_pieceRetryCount[piece]! >= 3) {
          _log.warning(
              'Piece $piece failed ${_pieceRetryCount[piece]} times, still retrying...');
        }

        _metaDataPieces.add(piece);
        _requestTimeout.remove(timeoutKey);
        _requestMetaData();
      });

      _requestTimeout[timeoutKey] = timer;
      targetPeer.sendExtendMessage('ut_metadata', msg);
      _log.fine(
          'Requested metadata piece $piece from peer ${targetPeer.address}');
    }
  }

  @override
  Iterable<Peer> get activePeers => _activePeers;

  @override
  void addPEXPeer(source, CompactAddress address, Map options) {
    // Skip PEX for private torrents (BEP 0027)
    if (_isPrivate) {
      _log.fine('Skipping PEX peer for private torrent');
      return;
    }

    if ((options['utp'] != null || options['ut_holepunch'] != null) &&
        options['reachable'] == null) {
      var peer = source as Peer;
      var message = getRendezvousMessage(address);
      peer.sendExtendMessage('ut_holepunch', message);
      return;
    }
    addNewPeerAddress(address, PeerSource.pex);
  }

  @override
  void holePunchConnect(CompactAddress ip) {
    addNewPeerAddress(ip, PeerSource.holepunch, PeerType.UTP);
  }

  @override
  void holePunchError(String err, CompactAddress ip) {}

  @override
  void holePunchRendezvous(CompactAddress ip) {}

  @override
  Future<Map<String, dynamic>> getOptions(Uri uri, String infoHash) {
    var map = {
      'downloaded': 0,
      'uploaded': 0,
      'left': 16 * 1024 * 20,
      'numwant': 50,
      'compact': 1,
      'peerId': _localPeerId,
      'port': 0
    };
    return Future.value(map);
  }
}
