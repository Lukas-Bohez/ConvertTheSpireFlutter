import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dtorrent_task_v2/src/torrent/torrent_model.dart';
import 'package:dtorrent_task_v2/src/torrent/torrent_file_model.dart';
import 'package:dtorrent_task_v2/src/file/download_file_manager_events.dart';
import 'package:dtorrent_task_v2/src/httpserver/server.dart';
import 'package:dtorrent_task_v2/src/lsd/lsd_events.dart';
import 'package:dtorrent_task_v2/src/peer/protocol/peer_events.dart';
import 'package:dtorrent_task_v2/src/peer/swarm/peers_manager_events.dart';
import 'package:dtorrent_task_v2/src/piece/piece_base.dart';
import 'package:dtorrent_task_v2/src/piece/piece_manager_events.dart';
import 'package:dtorrent_task_v2/src/peer/protocol/peer_events.dart'
    as peer_events;
import 'package:dtorrent_task_v2/src/piece/sequential_piece_selector.dart';
import 'package:dtorrent_task_v2/src/piece/piece_selector.dart';
import 'package:dtorrent_task_v2/src/piece/sequential_config.dart';
import 'package:dtorrent_task_v2/src/piece/sequential_stats.dart';
import 'package:dtorrent_task_v2/src/piece/advanced_sequential_selector.dart';
import 'package:dtorrent_task_v2/src/task_events.dart';
import 'package:dtorrent_tracker/dtorrent_tracker.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:bittorrent_dht/bittorrent_dht.dart';
import 'package:logging/logging.dart';
import 'package:events_emitter2/events_emitter2.dart';
import 'file/download_file_manager.dart';
import 'file/state_file.dart';
import 'file/state_file_v2.dart';
import 'lsd/lsd.dart';
import 'peer/protocol/peer.dart';
import 'piece/base_piece_selector.dart';
import 'peer/swarm/peers_manager.dart';
import 'piece/web_seed_downloader.dart';
import 'utils.dart';
import 'utils/debouncer.dart';
import 'torrent/torrent_version.dart';
import 'tracker/scrape_client.dart' as scrape;
import 'nat/port_forwarding_manager.dart';
import 'filter/ip_filter.dart';
import 'proxy/proxy_config.dart';
import 'proxy/proxy_manager.dart';
import 'seeding/superseeder.dart';
import 'file/file_priority.dart';
import 'file/file_priority_manager.dart';

const MAX_PEERS = 50;
const MAX_IN_PEERS = 10;

enum TaskState { running, paused, stopped }

var _log = Logger('TorrentTask');

abstract class TorrentTask with EventsEmittable<TaskEvent> {
  factory TorrentTask.newTask(
    TorrentModel metaInfo,
    String savePath, [
    bool stream = false,
    List<Uri>? webSeeds,
    List<Uri>? acceptableSources,
    SequentialConfig? sequentialConfig,
    ProxyConfig? proxyConfig,
  ]) {
    return _TorrentTask(
      metaInfo,
      savePath,
      stream: stream,
      webSeeds: webSeeds,
      acceptableSources: acceptableSources,
      sequentialConfig: sequentialConfig,
      proxyConfig: proxyConfig,
    );
  }
  void startAnnounceUrl(Uri url, Uint8List infoHash);
  TorrentModel get metaInfo;

  // The name of the torrent
  String get name => metaInfo.name;

  StateFile? get stateFile;

  /// The file manager
  DownloadFileManager? get fileManager;

  /// The peers manager
  PeersManager? get peersManager;

  // The dht instance

  DHT? get dht;

  int get allPeersNumber;

  int get connectedPeersNumber;

  int get seederNumber;

  /// Current download speed
  double get currentDownloadSpeed;

  /// Current upload speed
  double get uploadSpeed;

  /// Average download speed
  double get averageDownloadSpeed;

  /// Average upload speed
  double get averageUploadSpeed;

  // TODO debug:
  double get utpDownloadSpeed;
  // TODO debug:
  double get utpUploadSpeed;
  // TODO debug:
  int get utpPeerCount;

  /// Downloaded total bytes length
  int? get downloaded;

  /// Downloaded percent
  double get progress;

  /// Start to download
  Future<Map> start();

  // Start streaming videos
  Future<void> startStreaming();

  /// Stop this task
  Future stop();

  // Dispose task object

  Future<void> dispose();

  abstract TaskState state;
  Iterable<Peer>? get activePeers;
  PieceManager? get pieceManager;

  /// Pause task
  void pause();

  /// Resume task
  void resume();

  /// Apply selected file indices from magnet link (BEP 0053)
  /// Sets priority pieces for the specified file indices
  ///
  /// Example:
  /// ```dart
  /// task.applySelectedFiles([0, 2]); // Only download files at indices 0 and 2
  /// ```
  void applySelectedFiles(List<int> fileIndices);

  /// Set priority for a single file
  ///
  /// [fileIndex] - Index of the file (0-based)
  /// [priority] - Priority level (skip, low, normal, high)
  ///
  /// Example:
  /// ```dart
  /// task.setFilePriority(0, FilePriority.high); // Set first file to high priority
  /// ```
  void setFilePriority(int fileIndex, FilePriority priority);

  /// Set priorities for multiple files
  ///
  /// [priorities] - Map of file index to priority
  ///
  /// Example:
  /// ```dart
  /// task.setFilePriorities({
  ///   0: FilePriority.high,   // First file - high priority
  ///   1: FilePriority.normal,  // Second file - normal
  ///   2: FilePriority.skip,    // Third file - skip
  /// });
  /// ```
  void setFilePriorities(Map<int, FilePriority> priorities);

  /// Get priority for a file
  ///
  /// [fileIndex] - Index of the file (0-based)
  ///
  /// Returns the current priority of the file, or [FilePriority.normal] if not set.
  FilePriority getFilePriority(int fileIndex);

  /// Automatically prioritize files based on their type
  ///
  /// This method analyzes file extensions and sets priorities:
  /// - Video/audio files (mp4, mkv, avi, mp3, flac, etc.) -> high priority
  /// - Subtitle files (srt, ass, vtt, etc.) -> normal priority
  /// - Other files -> low priority
  ///
  /// Example:
  /// ```dart
  /// task.autoPrioritizeFiles();
  /// ```
  void autoPrioritizeFiles();

  void requestPeersFromDHT();

  /// Adding a DHT node usually involves adding the nodes from the torrent file into the DHT network.
  ///
  /// Alternatively, you can directly add known node addresses.
  void addDHTNode(Uri uri);

  /// Add known Peer addresses.
  void addPeer(CompactAddress address, PeerSource source,
      {PeerType? type, Socket socket});

  Stream<List<int>>? createStream({
    int filePosition = 0,
    int? endPosition,
    String? fileName,
  });

  /// Set current playback position for sequential download optimization
  ///
  /// This method updates the priority pieces based on the current playback
  /// position, ensuring smooth streaming during seek operations.
  ///
  /// [bytePosition] - Current playback position in bytes
  void setPlaybackPosition(int bytePosition);

  /// Get sequential download statistics
  ///
  /// Returns metrics including buffer health, time to first byte,
  /// download strategy, and seek statistics.
  SequentialStats? getSequentialStats();

  /// Scrape tracker for torrent statistics (BEP 48)
  ///
  /// Performs a scrape request to get torrent statistics (seeders, leechers, downloads)
  /// without performing a full announce.
  ///
  /// [trackerUrl] - Optional tracker URL. If not provided, uses first tracker from torrent.
  ///
  /// Returns [scrape.ScrapeResult] with statistics for the torrent's info hash.
  ///
  /// Example:
  /// ```dart
  /// final result = await task.scrapeTracker();
  /// if (result.isSuccess) {
  ///   final stats = result.getStatsForInfoHash(task.metaInfo.infoHash);
  ///   print('Seeders: ${stats?.complete}, Leechers: ${stats?.incomplete}');
  /// }
  /// ```
  Future<scrape.ScrapeResult> scrapeTracker([Uri? trackerUrl]);

  /// Set IP filter for blocking/allowing peer connections
  ///
  /// [filter] - IP filter instance. Set to null to disable filtering.
  ///
  /// Example:
  /// ```dart
  /// final filter = IPFilter();
  /// filter.addCIDRFromString('192.168.1.0/24');
  /// filter.setMode(IPFilterMode.blacklist);
  /// task.setIPFilter(filter);
  /// ```
  void setIPFilter(IPFilter? filter);

  /// Set proxy configuration
  ///
  /// [config] - Proxy configuration. Set to null to disable proxy.
  ///
  /// Example:
  /// ```dart
  /// final proxy = ProxyConfig.socks5(
  ///   host: 'proxy.example.com',
  ///   port: 1080,
  ///   username: 'user',
  ///   password: 'pass',
  /// );
  /// task.setProxyConfig(proxy);
  /// ```
  void setProxyConfig(ProxyConfig? config);

  /// Enable superseeding mode (BEP 16)
  ///
  /// Superseeding is a seeding algorithm designed to help a torrent initiator
  /// with limited bandwidth "pump up" a large torrent, reducing the amount of
  /// data it needs to upload in order to spawn new seeds.
  ///
  /// **Important**: Superseeding is NOT recommended for general use. It should
  /// only be used for initial seeding when you are the only or primary seeder.
  ///
  /// The mode will only be active when the client is a seeder (has all pieces).
  ///
  /// Example:
  /// ```dart
  /// task.enableSuperseeding();
  /// ```
  void enableSuperseeding();

  /// Disable superseeding mode
  ///
  /// Example:
  /// ```dart
  /// task.disableSuperseeding();
  /// ```
  void disableSuperseeding();

  /// Check if superseeding is enabled
  bool get isSuperseedingEnabled;
}

class _TorrentTask
    with EventsEmittable<TaskEvent>
    implements TorrentTask, AnnounceOptionsProvider {
  static InternetAddress LOCAL_ADDRESS =
      InternetAddress.fromRawAddress(Uint8List.fromList([127, 0, 0, 1]));

  TorrentAnnounceTracker? _tracker;

  scrape.ScrapeClient? _scrapeClient;

  PortForwardingManager? _portForwardingManager;

  IPFilter? _ipFilter;

  ProxyManager? _proxyManager;

  DHT? _dht = DHT();

  @override
  // The Dht instance
  DHT? get dht => _dht;

  LSD? _lsd;

  dynamic _stateFile; // Can be StateFile or StateFileV2

  @override
  StateFile? get stateFile {
    // StateFileV2 implements the same interface as StateFile
    // Both have bitfield, uploaded, downloaded properties
    return _stateFile as StateFile?;
  }

  PieceManager? _pieceManager;

  @override
  PieceManager? get pieceManager => _pieceManager;

  DownloadFileManager? _fileManager;

  @override
  DownloadFileManager? get fileManager => _fileManager;

  PeersManager? _peersManager;

  @override
  PeersManager? get peersManager => _peersManager;

  StreamingServer? _streamingServer;

  bool stream;

  /// Web seed URLs from magnet link (BEP 0019)
  final List<Uri> _webSeeds;

  /// Acceptable source URLs from magnet link (BEP 0019)
  final List<Uri> _acceptableSources;

  /// Web seed downloader for HTTP/FTP seeding
  WebSeedDownloader? _webSeedDownloader;

  /// Sequential download configuration
  final SequentialConfig? _sequentialConfig;

  /// Advanced sequential piece selector (when streaming with config)
  AdvancedSequentialPieceSelector? _advancedSelector;

  /// SuperSeeder for BEP 16 Superseeding mode
  SuperSeeder? _superseeder;

  /// Whether superseeding is enabled
  bool _superseedingEnabled = false;

  /// File priority manager for managing file priorities
  FilePriorityManager? _filePriorityManager;

  /// The maximum size of the disk write cache.
  final int maxWriteBufferSize = MAX_WRITE_BUFFER_SIZE;

  final _flushIndicesBuffer = <int>{};
  @override
  Iterable<Peer>? get activePeers => _peersManager?.activePeers;

  final TorrentModel _metaInfo;
  @override
  TorrentModel get metaInfo => _metaInfo;

  @override
  String get name => metaInfo.name;

  final String _savePath;

  final Set<String> _peerIds = {};

  late String
      _peerId; // This is the generated local peer ID, which is different from the ID used in the Peer class.

  ServerSocket? _serverSocket;

  StreamSubscription<Socket>? _serverSocketListener;
  // ServerUTPSocket? _utpServer;

  final Set<InternetAddress> _comingIp = {};

  EventsListener<TorrentAnnounceEvent>? trackerListener;
  EventsListener<peer_events.PeerEvent>? peersManagerListener;
  EventsListener<DownloadFileManagerEvent>? fileManagerListener;
  EventsListener<PieceManagerEvent>? pieceManagerListener;
  EventsListener<LSDEvent>? lsdListener;
  EventsListener<DHTEvent>? _dhtListener;

  /// Debouncer for progress events (StateFileUpdated) - reduces UI update frequency
  /// Default delay: 300ms (between 250-500ms as recommended)
  Debouncer<StateFileUpdated>? _progressDebouncer;

  _TorrentTask(this._metaInfo, this._savePath,
      {this.stream = false,
      List<Uri>? webSeeds,
      List<Uri>? acceptableSources,
      SequentialConfig? sequentialConfig,
      ProxyConfig? proxyConfig})
      : _webSeeds = webSeeds ?? [],
        _acceptableSources = acceptableSources ?? [],
        _sequentialConfig = sequentialConfig {
    if (proxyConfig != null) {
      _proxyManager = ProxyManager(proxyConfig);
    }
    _peerId = generatePeerId();
    // Initialize progress debouncer with 300ms delay
    _progressDebouncer = Debouncer<StateFileUpdated>(
      const Duration(milliseconds: 300),
      (event) => events.emit(event),
    );
  }

  @override
  double get averageDownloadSpeed {
    if (_peersManager != null) {
      return _peersManager!.averageDownloadSpeed;
    } else {
      return 0.0;
    }
  }

  @override
  double get averageUploadSpeed {
    if (_peersManager != null) {
      return _peersManager!.averageUploadSpeed;
    } else {
      return 0.0;
    }
  }

  @override
  double get currentDownloadSpeed {
    if (_peersManager != null) {
      return _peersManager!.currentDownloadSpeed;
    } else {
      return 0.0;
    }
  }

  @override
  double get uploadSpeed {
    if (_peersManager != null) {
      return _peersManager!.uploadSpeed;
    } else {
      return 0.0;
    }
  }

  String? _infoHashString;

  Timer? _dhtRepeatTimer;

  Future<PeersManager> _init(TorrentModel model, String savePath) async {
    _lsd ??= LSD(model.infoHash, _peerId);
    _infoHashString ??= String.fromCharCodes(model.infoHashBuffer);
    _tracker ??= TorrentAnnounceTracker(this);
    _stateFile ??= await StateFileV2.getStateFile(savePath, model);

    // Initialize file priority manager
    _filePriorityManager ??= FilePriorityManager(model);

    // Load file priorities from state file if available
    if (_stateFile != null && _stateFile is StateFileV2) {
      final stateFileV2 = _stateFile as StateFileV2;
      final savedPriorities = stateFileV2.filePriorities;
      if (savedPriorities.isNotEmpty) {
        _filePriorityManager!.setPriorities(savedPriorities);
        _log.info(
            'Loaded ${savedPriorities.length} file priorities from state file');
      }
    }

    // Initialize piece manager with appropriate selector
    if (_pieceManager == null) {
      PieceSelector selector;

      if (stream && _sequentialConfig != null) {
        // Use advanced sequential selector with configuration
        final advancedSelector =
            AdvancedSequentialPieceSelector(_sequentialConfig!);
        if (model.pieces != null) {
          advancedSelector.initialize(model.pieces!.length, model.pieceLength);
        }

        // Auto-detect moov atom if enabled
        if (_sequentialConfig!.autoDetectMoovAtom && model.length != null) {
          advancedSelector.detectAndSetMoovAtom(
              model.length!, model.pieceLength);
        }

        _advancedSelector = advancedSelector;
        selector = advancedSelector;
        _log.info(
            'Using AdvancedSequentialPieceSelector with config: $_sequentialConfig');
      } else if (stream) {
        // Use basic sequential selector
        selector = SequentialPieceSelector();
        _log.info('Using basic SequentialPieceSelector');
      } else {
        // Use rarest-first selector
        selector = BasePieceSelector();
        _log.info('Using BasePieceSelector (rarest-first)');
      }

      // Detect torrent version (v1, v2, or hybrid)
      final torrentVersion = TorrentVersionHelper.detectVersion(model);
      _log.info('Detected torrent version: $torrentVersion');

      _pieceManager = PieceManager.createPieceManager(
        selector,
        model,
        _stateFile!.bitfield,
        version: torrentVersion,
      );

      // Update piece priorities after piece manager is created
      if (_filePriorityManager != null) {
        _updatePiecePriorities();
      }
    }

    _fileManager ??= await DownloadFileManager.createFileManager(
        model, savePath, _stateFile!, _pieceManager!.pieces.values.toList());
    _peersManager ??= PeersManager(_peerId, model, ipFilter: _ipFilter);

    // Initialize SuperSeeder if superseeding is enabled
    if (_superseedingEnabled && _superseeder == null && model.pieces != null) {
      _superseeder = SuperSeeder(model.pieces!.length);
      // Only enable if we're already a seeder
      if (_fileManager != null && _fileManager!.isAllComplete) {
        _superseeder!.enable();
        _log.info(
            'SuperSeeder initialized and enabled for ${model.pieces!.length} pieces (client is a seeder)');
      } else {
        _log.info(
            'SuperSeeder initialized for ${model.pieces!.length} pieces (will be enabled when download completes)');
      }
    }
    // Set torrent version for v2/hybrid support in peer handshakes
    if (_peersManager != null) {
      final torrentVersion = TorrentVersionHelper.detectVersion(model);
      _peersManager!.setTorrentVersion(torrentVersion);
    }

    // Initialize web seed downloader if web seeds are available (BEP 0019)
    if ((_webSeeds.isNotEmpty || _acceptableSources.isNotEmpty) &&
        _webSeedDownloader == null) {
      _webSeedDownloader = WebSeedDownloader(
        webSeeds: _webSeeds,
        acceptableSources: _acceptableSources,
        totalLength: model.length ?? model.totalSize,
        pieceLength: model.pieceLength,
      );
      _log.info(
          'Initialized web seed downloader with ${_webSeeds.length} web seed(s) and ${_acceptableSources.length} acceptable source(s)');
    }

    return _peersManager!;
  }

  void initStreaming() {
    _streamingServer ??= StreamingServer(_fileManager!, this);
  }

  @override
  Future<void> startStreaming() async {
    initStreaming();
    await _init(_metaInfo, _savePath);
    for (var file in _fileManager!.files) {
      await file.requestFlush();
    }
    if (!_streamingServer!.running) {
      await _streamingServer?.start().then((event) => events.emit(event));
    }
  }

  @override
  Stream<List<int>>? createStream(
      {int filePosition = 0, int? endPosition, String? fileName}) {
    if (_fileManager == null ||
        _peersManager == null ||
        _pieceManager == null) {
      return null;
    }
    TorrentFileModel file;
    if (fileName != null) {
      file = _fileManager!.metainfo.files
          .firstWhere((file) => file.name == fileName);
    } else {
      file = _fileManager!.metainfo.files.firstWhere(
        (file) => file.name.contains('mp4'),
        orElse: () => _fileManager!.metainfo.files.first,
      );
    }
    var localFile = _fileManager?.files.firstWhere(
        (downloadedFile) => downloadedFile.originalFileName == file.name);

    if (localFile == null) return null;
    // if no end position provided, read all file
    endPosition ??= file.length;

    var offsetStart = file.offset + filePosition;
    var offsetEnd = file.offset + endPosition;

    var startPieceIndex = offsetStart ~/ metaInfo.pieceLength;
    var endPieceIndex = offsetEnd ~/ metaInfo.pieceLength;

    _pieceManager!.pieceSelector.setPriorityPieces(
        {for (var i = startPieceIndex; i <= endPieceIndex; i++) i});

    var stream = localFile.createStream(filePosition, endPosition);
    if (stream == null) return null;

    return stream;
  }

  @override
  void setPlaybackPosition(int bytePosition) {
    if (_advancedSelector == null || _pieceLength == null) {
      _log.warning(
          'Cannot set playback position: advanced selector not initialized');
      return;
    }

    _advancedSelector!.setPlaybackPosition(bytePosition, _pieceLength!);
    _log.fine(
        'Playback position set to: ${(bytePosition / 1024 / 1024).toStringAsFixed(2)} MB');
  }

  @override
  SequentialStats? getSequentialStats() {
    if (_advancedSelector == null || _pieceManager == null) {
      return null;
    }

    return _advancedSelector!.getStats(_pieceManager!);
  }

  int? get _pieceLength => _metaInfo.pieceLength;

  @override
  void addPeer(CompactAddress address, PeerSource source,
      {PeerType? type, Socket? socket}) {
    _peersManager?.addNewPeerAddress(address, source,
        type: type, socket: socket);
  }

  void _whenTaskDownloadComplete() async {
    await _peersManager
        ?.disposeAllSeeder('Download complete,disconnect seeder');
    await _tracker?.complete();
    events.emit(TaskCompleted());
  }

  void _whenFileDownloadComplete(DownloadManagerFileCompleted event) {
    events.emit(TaskFileCompleted(event.file));
  }

  void _processTrackerPeerEvent(AnnouncePeerEventEvent event) {
    if (event.event == null) return;
    var ps = event.event!.peers;
    if (ps.isNotEmpty) {
      for (var url in ps) {
        _processNewPeerFound(url, PeerSource.tracker);
      }
    }
  }

  void _processLSDPeerEvent(LSDNewPeer event) {
    print('There is LSD! !');
  }

  void _processNewPeerFound(CompactAddress url, PeerSource source) {
    _log.info(
      "Add new peer ${url.toString()} from ${source.name} to peersManager",
    );
    _peersManager?.addNewPeerAddress(url, source);
  }

  void _processDHTPeer(CompactAddress peer, String infoHash) {
    _log.fine(
      "Got new peer from $peer DHT for infohash: ${Uint8List.fromList(infoHash.codeUnits).toHexString()}",
    );
    if (infoHash == _infoHashString) {
      _processNewPeerFound(peer, PeerSource.dht);
    }
  }

  void _hookInPeer(Socket socket) {
    if (socket.remoteAddress == LOCAL_ADDRESS) {
      socket.close();
      return;
    }
    if (_comingIp.length >= MAX_IN_PEERS || !_comingIp.add(socket.address)) {
      socket.close();
      return;
    }
    _log.info(
      'incoming connect: ${socket.remoteAddress.address}:${socket.remotePort}',
    );
    _peersManager?.addNewPeerAddress(
        CompactAddress(socket.remoteAddress, socket.remotePort),
        PeerSource.incoming,
        type: PeerType.TCP,
        socket: socket);
  }

  @override
  void pause() {
    if (state == TaskState.paused) return;
    state = TaskState.paused;
    _peersManager?.pause();
    events.emit(TaskPaused());
  }

  @override
  TaskState state = TaskState.stopped;

  @override
  void resume() {
    if (state == TaskState.paused) {
      state = TaskState.running;
      _peersManager?.resume();
      events.emit(TaskResumed());
    }
  }

  @override
  void applySelectedFiles(List<int> fileIndices) {
    if (_fileManager == null || _pieceManager == null) {
      _log.warning(
          'Cannot apply selected files: fileManager or pieceManager not initialized');
      return;
    }

    if (fileIndices.isEmpty) {
      _log.warning('No file indices provided');
      return;
    }

    // Validate indices
    final validIndices = fileIndices
        .where((index) => index >= 0 && index < _metaInfo.files.length)
        .toList();

    if (validIndices.isEmpty) {
      _log.warning('No valid file indices provided');
      return;
    }

    // Collect all pieces that belong to selected files
    final priorityPieces = <int>{};

    for (var fileIndex in validIndices) {
      final file = _metaInfo.files[fileIndex];
      final startPiece = file.offset ~/ _metaInfo.pieceLength;
      var endPiece = file.end ~/ _metaInfo.pieceLength;
      // Adjust endPiece if file.end is exactly on piece boundary
      if (file.end.remainder(_metaInfo.pieceLength) == 0) {
        endPiece--;
      }

      // Add all pieces for this file
      if (_metaInfo.pieces != null) {
        for (var pieceIndex = startPiece;
            pieceIndex <= endPiece;
            pieceIndex++) {
          if (pieceIndex >= 0 && pieceIndex < _metaInfo.pieces!.length) {
            priorityPieces.add(pieceIndex);
          }
        }
      }
    }

    if (priorityPieces.isNotEmpty) {
      _pieceManager!.pieceSelector.setPriorityPieces(priorityPieces);
      _log.info(
          'Applied selected files (indices: $validIndices) - ${priorityPieces.length} pieces prioritized');
    } else {
      _log.warning('No pieces found for selected file indices: $validIndices');
    }
  }

  @override
  void setFilePriority(int fileIndex, FilePriority priority) {
    if (_filePriorityManager == null) {
      _log.warning('FilePriorityManager not initialized');
      return;
    }

    _filePriorityManager!.setPriority(fileIndex, priority);
    _updatePiecePriorities();
    _log.info('Set priority for file $fileIndex: $priority');
  }

  @override
  void setFilePriorities(Map<int, FilePriority> priorities) {
    if (_filePriorityManager == null) {
      _log.warning('FilePriorityManager not initialized');
      return;
    }

    _filePriorityManager!.setPriorities(priorities);
    _updatePiecePriorities();
    _saveFilePriorities();
    _log.info('Set priorities for ${priorities.length} files');
  }

  @override
  FilePriority getFilePriority(int fileIndex) {
    if (_filePriorityManager == null) {
      return FilePriority.normal;
    }
    return _filePriorityManager!.getPriority(fileIndex);
  }

  @override
  void autoPrioritizeFiles() {
    if (_filePriorityManager == null) {
      _log.warning('FilePriorityManager not initialized');
      return;
    }

    // Video file extensions
    final videoExtensions = {
      'mp4',
      'mkv',
      'avi',
      'mov',
      'wmv',
      'flv',
      'webm',
      'm4v',
      'mpg',
      'mpeg',
      '3gp',
      'ogv',
      'ts',
      'm2ts'
    };

    // Audio file extensions
    final audioExtensions = {
      'mp3',
      'flac',
      'wav',
      'aac',
      'ogg',
      'opus',
      'm4a',
      'wma',
      'ape',
      'dsd'
    };

    // Subtitle file extensions
    final subtitleExtensions = {
      'srt',
      'ass',
      'ssa',
      'vtt',
      'sub',
      'idx',
      'sup'
    };

    for (var i = 0; i < _metaInfo.files.length; i++) {
      final file = _metaInfo.files[i];
      final fileName = file.path.toLowerCase();
      final extension = fileName.split('.').last;

      if (videoExtensions.contains(extension) ||
          audioExtensions.contains(extension)) {
        _filePriorityManager!.setPriority(i, FilePriority.high);
      } else if (subtitleExtensions.contains(extension)) {
        _filePriorityManager!.setPriority(i, FilePriority.normal);
      } else {
        _filePriorityManager!.setPriority(i, FilePriority.low);
      }
    }

    _updatePiecePriorities();
    _saveFilePriorities();
    _log.info('Auto-prioritized files based on file types');
  }

  /// Save file priorities to state file
  void _saveFilePriorities() {
    if (_filePriorityManager == null || _stateFile == null) {
      return;
    }

    if (_stateFile is StateFileV2) {
      final stateFileV2 = _stateFile as StateFileV2;
      final allPriorities = _filePriorityManager!.getAllPriorities();
      stateFileV2.setFilePriorities(allPriorities);
      _log.fine('Saved file priorities to state file');
    }
  }

  /// Update piece priorities based on file priorities
  void _updatePiecePriorities() {
    if (_filePriorityManager == null || _pieceManager == null) {
      return;
    }

    // Get pieces by priority
    final piecesByPriority = _filePriorityManager!.getPiecesByPriority();

    // Set priority pieces: high priority first, then normal, then low
    final priorityPieces = <int>{};
    priorityPieces.addAll(piecesByPriority[FilePriority.high]!);
    priorityPieces.addAll(piecesByPriority[FilePriority.normal]!);
    priorityPieces.addAll(piecesByPriority[FilePriority.low]!);

    // Update piece selector
    _pieceManager!.pieceSelector.setPriorityPieces(priorityPieces);

    // Mark skipped pieces (if any)
    final skippedPieces = piecesByPriority[FilePriority.skip]!;
    if (skippedPieces.isNotEmpty) {
      _pieceManager!.pieceSelector.setSkippedPieces(skippedPieces);
      _log.info('Skipping ${skippedPieces.length} pieces from skipped files');
    } else {
      _pieceManager!.pieceSelector.setSkippedPieces([]);
    }
  }

  @override
  Future<Map> start() async {
    state = TaskState.running;
    // Incoming peer:
    _serverSocket ??= await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    await _init(_metaInfo, _savePath);
    _serverSocketListener = _serverSocket?.listen(_hookInPeer);

    // Try to forward port automatically (non-blocking)
    _forwardPortIfAvailable();
    // _utpServer ??= await ServerUTPSocket.bind(
    //     InternetAddress.anyIPv4, _serverSocket?.port ?? 0);
    // _utpServer?.listen(_hookUTP);

    var map = {};
    map['name'] = _metaInfo.name;
    map['tcp_socket'] = _serverSocket?.port;
    map['complete_pieces'] = List.from(_stateFile!.bitfield.completedPieces);
    map['total_pieces_num'] = _stateFile!.bitfield.piecesNum;
    map['downloaded'] = _stateFile!.downloaded;
    map['uploaded'] = _stateFile!.uploaded;
    map['total_length'] = _metaInfo.length;
    // Outgoing peer:
    trackerListener = _tracker?.createListener();
    peersManagerListener = _peersManager?.createListener();
    fileManagerListener = _fileManager?.createListener();
    pieceManagerListener = _pieceManager?.createListener();
    lsdListener = _lsd?.createListener();
    trackerListener?.on<AnnouncePeerEventEvent>(_processTrackerPeerEvent);

    peersManagerListener
      ?..on<PeerAllowFast>(_processAllowFast)
      ..on<PeerRejectEvent>(_processRejectRequest)
      ..on<PeerDisposeEvent>(_processPeerDispose)
      ..on<PeerPieceEvent>(_processReceivePiece)
      ..on<PeerRequestEvent>(_processPeerRequest)
      ..on<PeerHandshakeEvent>(_processPeerHandshake)
      ..on<PeerBitfieldEvent>(_processBitfieldUpdate)
      ..on<PeerHaveAll>(_processHaveAll)
      ..on<PeerHaveNone>(_processHaveNone)
      ..on<PeerChokeChanged>(_processChokeChange)
      ..on<PeerHaveEvent>(_processHaveUpdate)
      ..on<RequestTimeoutEvent>(
          (event) => _processRequestTimeout(event.peer, event.requests))
      ..on<UpdateUploaded>(
          (event) => _fileManager?.updateUpload(event.uploaded));
    fileManagerListener
      ?..on<DownloadManagerFileCompleted>(_whenFileDownloadComplete)
      ..on<StateFileUpdated>((event) {
        // Use debouncer to reduce UI update frequency
        _progressDebouncer?.call(StateFileUpdated());
      })
      ..on<SubPieceReadCompleted>((event) => _peersManager
          ?.readSubPieceComplete(event.pieceIndex, event.begin, event.block));
    pieceManagerListener
      ?..on<PieceAccepted>((event) => processPieceAccepted(event.pieceIndex))
      ..on<PieceRejected>((event) => null);
    lsdListener?.on<LSDNewPeer>(_processLSDPeerEvent);
    _lsd?.port = _serverSocket?.port;
    try {
      await _lsd?.start();
    } catch (e) {
      // Ignore port conflicts for LSD (port 6771) - it's not critical for functionality
      if (e is SocketException &&
          (e.message.contains('Address already in use') ||
              e.osError?.errorCode == 48)) {
        _log.warning('LSD port 6771 is already in use, continuing without LSD');
      } else {
        rethrow;
      }
    }
    _dhtListener = _dht?.createListener();
    _dhtListener?.on<NewPeerEvent>(
        (event) => _processDHTPeer(event.address, event.infoHash));
    _dht?.announce(
        String.fromCharCodes(_metaInfo.infoHashBuffer), _serverSocket!.port);

    _dht?.bootstrap();

    if (_fileManager != null && _fileManager!.isAllComplete) {
      _tracker?.complete();
    } else {
      _tracker?.runTrackers(_metaInfo.announces, _metaInfo.infoHashBuffer,
          event: EVENT_STARTED);
    }
    events.emit(TaskStarted());
    return map;
  }

  void processPieceRejected(int index) {
    var piece = _pieceManager?[index];
    if (piece == null) return;

    // Try web seed if no peers available (BEP 0019)
    if (piece.availablePeers.isEmpty && _webSeedDownloader != null) {
      _tryDownloadPieceFromWebSeed(index);
      return;
    }

    // TODO: still need optimizing for last pieces
    for (var peer in piece.availablePeers) {
      requestPieces(peer, piece.index);
    }
  }

  /// Try to download a piece from web seed (BEP 0019)
  Future<void> _tryDownloadPieceFromWebSeed(int pieceIndex) async {
    if (_webSeedDownloader == null ||
        _pieceManager == null ||
        _fileManager == null) {
      return;
    }

    final piece = _pieceManager![pieceIndex];
    if (piece == null || _fileManager!.localHave(pieceIndex)) {
      return;
    }

    // Calculate piece offset and size
    final pieceOffset = piece.offset;
    final pieceSize = piece.byteLength;

    try {
      _log.fine('Attempting to download piece $pieceIndex from web seed');
      final data = await _webSeedDownloader!.downloadPiece(
        pieceIndex,
        pieceOffset,
        pieceSize,
      );

      if (data != null && data.length == pieceSize) {
        // Process the downloaded piece as if it came from a peer
        // Write it in blocks to match the normal flow
        final blockSize = DEFAULT_REQUEST_LENGTH;
        for (var begin = 0; begin < pieceSize; begin += blockSize) {
          final end =
              (begin + blockSize < pieceSize) ? begin + blockSize : pieceSize;
          final block = data.sublist(begin, end);
          _pieceManager!.processReceivedBlock(pieceIndex, begin, block);
        }

        _log.info('Successfully downloaded piece $pieceIndex from web seed');
      } else {
        _log.warning(
            'Failed to download piece $pieceIndex from web seed: invalid data');
      }
    } catch (e) {
      _log.warning('Error downloading piece $pieceIndex from web seed: $e');
    }
  }

  Future<void> processPieceAccepted(int index) async {
    var piece = _pieceManager?[index];
    if (piece == null || _fileManager == null || _pieceManager == null) return;

    var block = piece.flush();
    if (block == null) return;

    if (_fileManager!.localHave(index)) return;
    var written = await _fileManager!.writeFile(
      index,
      0,
      block,
    );

    if (!written) return;
    _pieceManager!.processPieceWriteComplete(index);
    await _fileManager!.updateBitfield(index);

    // In superseeding mode, send HAVE only to specific peers for specific pieces
    if (_superseeder != null && _fileManager!.isAllComplete) {
      _sendHaveSuperseeding(index);
    } else {
      _peersManager?.sendHaveToAll(index);
    }
    _flushIndicesBuffer.add(index);
    await _flushFiles(_flushIndicesBuffer);
    if (_fileManager!.isAllComplete) {
      events.emit(AllComplete());
      _whenTaskDownloadComplete();

      // Enable superseeding if it was requested but we weren't a seeder yet
      if (_superseedingEnabled &&
          _superseeder != null &&
          !_superseeder!.enabled) {
        _superseeder!.enable();
        _log.info(
            'Superseeding activated (download completed, client is now a seeder)');
      }
    }
  }

  /// Send HAVE messages in superseeding mode
  /// Only sends HAVE for pieces that should be announced to specific peers
  void _sendHaveSuperseeding(int pieceIndex) {
    if (_superseeder == null || _peersManager == null) return;

    // In superseeding mode, we don't send HAVE for completed pieces
    // Instead, we only send HAVE for pieces that SuperSeeder selects
    // This method is called when a piece is completed, but in superseeding mode
    // we're already a seeder, so this shouldn't normally be called
    // However, we handle it gracefully by not sending HAVE
    _log.fine(
        'Superseeding: Not sending HAVE for piece $pieceIndex (superseeding mode)');
  }

  Future _flushFiles(Set<int> indices) async {
    if (indices.isEmpty || _fileManager == null) return;
    var piecesSize = _metaInfo.pieceLength;
    var buffer = indices.length * piecesSize;
    if (buffer >= maxWriteBufferSize || _fileManager!.isAllComplete) {
      var temp = Set<int>.from(indices);
      indices.clear();
      await _fileManager?.flushFiles(temp);
    }
    return;
  }

  /// Even if the other peer has choked me, I can still download.
  void _processAllowFast(PeerAllowFast event) {
    var piece = _pieceManager?[event.index];
    if (piece != null && piece.haveAvailableSubPiece()) {
      piece.addAvailablePeer(event.peer);
      _pieceManager?.processDownloadingPiece(event.index);
      requestPieces(event.peer, event.index);
    }
  }

  void _processRejectRequest(PeerRejectEvent event) {
    var piece = _pieceManager?[event.index];
    piece?.pushSubPieceLast(event.begin ~/ DEFAULT_REQUEST_LENGTH);
  }

  void _processPeerDispose(PeerDisposeEvent event) {
    if (_pieceManager == null) return;

    // Clean up superseeding tracking for this peer
    if (_superseeder != null) {
      _superseeder!.onPeerDisconnected(event.peer);
    }
    var bufferRequests = event.peer.requestBuffer;

    _pushSubPiecesBack(bufferRequests);
    var completedPieces = event.peer.remoteCompletePieces;
    for (var index in completedPieces) {
      _pieceManager![index]?.removeAvailablePeer(event.peer);
    }
  }

  void _pushSubPiecesBack(List<List<int>> requests) {
    if (requests.isEmpty || _pieceManager == null) return;
    for (var element in requests) {
      var pieceIndex = element[0];
      var begin = element[1];
      // TODO This is dangerous here. Currently, we are dividing a piece into 16 KB chunks. What if it's not the case?
      var piece = _pieceManager![pieceIndex];
      var subindex = begin ~/ DEFAULT_REQUEST_LENGTH;
      piece?.pushSubPiece(subindex);
    }
  }

  void _processReceivePiece(PeerPieceEvent event) {
    if (_pieceManager == null || _peersManager == null) return;

    var piece = _pieceManager![event.index];
    var i = event.index;
    if (piece != null) {
      var blockStart = piece.offset + event.begin;
      var blockEnd = blockStart + event.block.length;
      if (blockEnd > piece.end) {
        _log.info('Error:', 'Piece overlaps with next piece');
        // will request the same piece below
      } else {
        if (!piece.isCompleted) {
          pieceManager?.processReceivedBlock(
              event.index, event.begin, event.block);
        }
        // request available subpiece
        if (piece.haveAvailableSubPiece()) i = -1;
      }
    }

    Timer.run(() => requestPieces(event.peer, i));
  }

  void _processPeerHandshake(PeerHandshakeEvent event) {
    if (_fileManager == null) return;

    // In superseeding mode, don't send bitfield (masquerade as peer with no data)
    // Instead, send HAVE for a selected rare piece
    if (_superseeder != null &&
        _superseeder!.enabled &&
        _fileManager!.isAllComplete) {
      _log.fine(
          'Superseeding: Not sending bitfield to peer ${event.peer.address}');

      // Select a piece to offer to this peer
      final pieceToOffer = _superseeder!.selectPieceToOffer(event.peer);
      if (pieceToOffer != null) {
        // Send HAVE for the selected piece
        Timer.run(() {
          event.peer.sendHave(pieceToOffer);
          _log.fine(
              'Superseeding: Sent HAVE for piece $pieceToOffer to peer ${event.peer.address}');
        });
      }
      return;
    }

    event.peer.sendBitfield(_fileManager!.localBitfield);
  }

  void _processPeerRequest(PeerRequestEvent event) {
    if (_fileManager == null ||
        _peersManager == null ||
        _peersManager!.isPaused) {
      return;
    }
    _fileManager!.readFile(event.index, event.begin, event.length);
  }

  void _processHaveAll(PeerHaveAll event) {
    _processBitfieldUpdate(
        PeerBitfieldEvent(event.peer, event.peer.remoteBitfield));
  }

  void _processHaveNone(PeerHaveNone event) {
    _processBitfieldUpdate(PeerBitfieldEvent(event.peer, null));
  }

  void _processBitfieldUpdate(PeerBitfieldEvent bitfieldEvent) {
    if (_fileManager == null || _pieceManager == null) return;
    if (bitfieldEvent.bitfield != null) {
      if (_fileManager!.isAllComplete && bitfieldEvent.peer.isSeeder) {
        bitfieldEvent.peer.dispose(BadException(
            "Do not connect to Seeder if the download is already completed"));
        return;
      }

      // Check if we need any pieces from this peer
      bool shouldBeInterested = false;
      for (var i = 0; i < _fileManager!.piecesNumber; i++) {
        if (bitfieldEvent.bitfield!.getBit(i)) {
          if (!_fileManager!.localHave(i)) {
            shouldBeInterested = true;
            break;
          }
        }
      }

      if (shouldBeInterested) {
        // Send interested if we haven't already
        if (!bitfieldEvent.peer.interestedRemote) {
          bitfieldEvent.peer.sendInterested(true);
        }

        // Check if peer is already unchoked - if so, start requesting immediately
        // This handles the race condition where peer sends unchoke before we send interested
        if (!bitfieldEvent.peer.chokeMe) {
          var completedPieces = bitfieldEvent.peer.remoteCompletePieces;
          for (var index in completedPieces) {
            if (_pieceManager![index] != null &&
                !_fileManager!.localHave(index)) {
              _pieceManager![index]?.addAvailablePeer(bitfieldEvent.peer);
            }
          }
          // Start requesting if peer is sleeping (has no active requests)
          if (bitfieldEvent.peer.isSleeping) {
            Timer.run(() => requestPieces(bitfieldEvent.peer));
          }
        }
      } else {
        bitfieldEvent.peer.sendInterested(false);
      }
    } else {
      bitfieldEvent.peer.sendInterested(false);
    }
  }

  void _processHaveUpdate(PeerHaveEvent event) {
    if (pieceManager == null || _fileManager == null || _peersManager == null) {
      return;
    }

    // Track piece distribution for superseeding
    if (_superseeder != null && _fileManager!.isAllComplete) {
      for (var index in event.indices) {
        _superseeder!.onPeerHave(event.peer, index);
      }
    }
    var canRequest = false;
    for (var index in event.indices) {
      if (_pieceManager![index] == null) continue;

      if (!_fileManager!.localHave(index)) {
        // if peer is choking us just send interested
        if (event.peer.chokeMe) {
          event.peer.sendInterested(true);
        } else {
          // not choking us, add the peer to the piece and request below
          canRequest = true;
          _pieceManager![index]?.addAvailablePeer(event.peer);
        }
      }
    }
    if (canRequest && event.peer.isSleeping) {
      // peer doesn't have requests, so we can request
      Timer.run(() => requestPieces(event.peer));
    }
  }

  void _processChokeChange(PeerChokeChanged event) {
    if (_pieceManager == null || _peersManager == null) return;
    // Update available peers for pieces.
    if (!event.choked) {
      var completedPieces = event.peer.remoteCompletePieces;
      for (var index in completedPieces) {
        _pieceManager![index]?.addAvailablePeer(event.peer);
      }
      // Start requesting
      Timer.run(() => requestPieces(event.peer));
    } else {
      var completedPieces = event.peer.remoteCompletePieces;
      for (var index in completedPieces) {
        _pieceManager![index]?.removeAvailablePeer(event.peer);
      }
    }
  }

  void _processRequestTimeout(Peer peer, List<List<int>> requests) {
    if (_pieceManager == null || _peersManager == null) return;
    var flag = false;
    for (var request in requests) {
      if (request[4] >= 3) {
        flag = true;
        Timer.run(() => peer.requestCancel(request[0], request[1], request[2]));
        var index = request[0];
        var begin = request[1];
        var subindex = begin ~/ DEFAULT_REQUEST_LENGTH;
        var piece = _pieceManager![index];
        piece?.pushSubPiece(subindex);
      }
    }
    // Wake up other possibly idle peers.
    if (flag) {
      for (var p in _peersManager!.activePeers) {
        if (p != peer && p.isSleeping) {
          // TODO: should we request from all peers ?
          Timer.run(() => requestPieces(p));
        }
      }
    }
  }

  void requestPieces(Peer peer, [int pieceIndex = -1]) async {
    if (_pieceManager == null || _peersManager == null) return;
    if (_peersManager!.addPausedRequest(peer, pieceIndex)) return;
    Piece? piece;
    if (pieceIndex != -1) {
      // a specific piece requested
      piece = _pieceManager![pieceIndex];
      // if the piece is available but doesn't have available subpiece,
      // select a different subpiece
      if (piece != null && !piece.haveAvailableSubPiece()) {
        piece = _pieceManager!
            .selectPiece(peer, _pieceManager!, peer.remoteSuggestPieces);
      }
    } else {
      // no specific piece requested, select one
      piece = _pieceManager!
          .selectPiece(peer, _pieceManager!, peer.remoteSuggestPieces);
    }

    // at this point we have a piece that we know is:
    // - available in the peer
    // - have subPieces
    if (piece == null) {
      // If no piece available from peers, try web seed (BEP 0019)
      if (pieceIndex != -1 && _webSeedDownloader != null) {
        _tryDownloadPieceFromWebSeed(pieceIndex);
      }
      return;
    }

    var subIndex = piece.popSubPiece();
    if (subIndex == null) return;
    var size = DEFAULT_REQUEST_LENGTH; // Block size is calculated dynamically.
    var begin = subIndex * size;
    if ((begin + size) > piece.byteLength) {
      size = piece.byteLength - begin;
    }
    if (!peer.sendRequest(piece.index, begin, size)) {
      piece.pushSubPiece(subIndex);
    } else {
      Timer.run(() => requestPieces(peer, pieceIndex));
    }
  }

  @override
  Future stop([bool force = false]) async {
    await _tracker?.stop(force);
    await _streamingServer?.stop();
    events.emit(TaskStopped());
    await dispose();
  }

  @override
  Future<void> dispose() async {
    await _flushFiles(_flushIndicesBuffer);
    _flushIndicesBuffer.clear();
    events.dispose();
    _dhtRepeatTimer?.cancel();
    _dhtRepeatTimer = null;
    trackerListener?.dispose();
    fileManagerListener?.dispose();
    peersManagerListener?.dispose();
    lsdListener?.dispose();
    _dhtListener?.dispose();
    // Flush and dispose progress debouncer
    _progressDebouncer?.flush();
    _progressDebouncer?.dispose();
    // This is in order, first stop the tracker, then stop listening on the server socket and all peers, finally close the file system.
    await _tracker?.dispose();
    _tracker = null;

    await _peersManager?.dispose();
    _peersManager = null;
    _serverSocketListener?.cancel();
    _serverSocketListener = null;
    await _serverSocket?.close();
    _serverSocket = null;
    await _fileManager?.close();
    _fileManager = null;
    await _dht?.stop();
    _dht = null;
    _lsd?.close();
    _lsd = null;
    _peerIds.clear();
    _comingIp.clear();
    _streamingServer?.stop();

    // Dispose web seed downloader
    _webSeedDownloader?.dispose();
    _webSeedDownloader = null;

    // Remove port forwarding
    await _removePortForwarding();

    state = TaskState.stopped;
    return;
  }

  /// Forward port if port forwarding is available
  Future<void> _forwardPortIfAvailable() async {
    if (_serverSocket == null) return;

    try {
      _portForwardingManager ??= PortForwardingManager();
      final port = _serverSocket!.port;

      if (port > 0) {
        _log.info('Attempting to forward port $port...');
        final result = await _portForwardingManager!.forwardPort(port: port);

        if (result.success) {
          _log.info('Port $port forwarded successfully using ${result.method}');
          if (result.externalIP != null) {
            _log.info('External IP: ${result.externalIP}');
          }
        } else {
          _log.fine('Port forwarding not available: ${result.error}');
        }
      }
    } catch (e, stackTrace) {
      _log.warning('Error during port forwarding', e, stackTrace);
    }
  }

  /// Remove port forwarding
  Future<void> _removePortForwarding() async {
    if (_portForwardingManager == null || _serverSocket == null) return;

    try {
      final port = _serverSocket!.port;
      if (port > 0) {
        await _portForwardingManager!.removePortForwarding(port: port);
      }
    } catch (e, stackTrace) {
      _log.warning('Error removing port forwarding', e, stackTrace);
    }
  }

  @override
  Future<Map<String, dynamic>> getOptions(Uri uri, String infoHash) {
    var map = {
      'downloaded': _stateFile?.downloaded,
      'uploaded': _stateFile?.uploaded,
      'left': (_metaInfo.length ?? 0) - _stateFile!.downloaded,
      'numwant': 50,
      'compact': 1,
      'peerId': _peerId,
      'port': _serverSocket?.port
    };
    return Future.value(map);
  }

  @override
  int? get downloaded => _fileManager?.downloaded;

  @override
  double get progress {
    var d = downloaded;
    if (d == null) return 0.0;
    var l = _metaInfo.length;
    if (l == null) return 0.0;
    return d / l;
  }

  @override
  int get allPeersNumber {
    if (_peersManager != null) {
      return _peersManager!.peersNumber;
    } else {
      return 0;
    }
  }

  @override
  void addDHTNode(Uri url) {
    _dht?.addBootstrapNode(url);
  }

  @override
  int get connectedPeersNumber {
    if (_peersManager != null) {
      return _peersManager!.connectedPeersNumber;
    } else {
      return 0;
    }
  }

  @override
  int get seederNumber {
    if (_peersManager != null) {
      return _peersManager!.seederNumber;
    } else {
      return 0;
    }
  }

  // TODO debug:
  @override
  double get utpDownloadSpeed {
    if (_peersManager == null) return 0.0;
    return _peersManager!.utpDownloadSpeed;
  }

// TODO debug:
  @override
  double get utpUploadSpeed {
    if (_peersManager == null) return 0.0;
    return _peersManager!.utpUploadSpeed;
  }

// TODO debug:
  @override
  int get utpPeerCount {
    if (_peersManager == null) return 0;
    return _peersManager!.utpPeerCount;
  }

  @override
  void startAnnounceUrl(Uri url, Uint8List infoHash) {
    _tracker?.runTracker(url, infoHash);
  }

  @override
  void requestPeersFromDHT() {
    _dht?.requestPeers(String.fromCharCodes(_metaInfo.infoHashBuffer));
  }

  @override
  void setIPFilter(IPFilter? filter) {
    _ipFilter = filter;
    _peersManager?.setIPFilter(filter);
    _log.info('IP filter ${filter != null ? "enabled" : "disabled"}');
  }

  @override
  void setProxyConfig(ProxyConfig? config) {
    _proxyManager = config != null ? ProxyManager(config) : null;
    _peersManager?.setProxyManager(_proxyManager);
    _log.info('Proxy ${config != null ? "enabled" : "disabled"}');
  }

  @override
  void enableSuperseeding() {
    if (_superseedingEnabled) {
      _log.warning('Superseeding is already enabled');
      return;
    }

    _superseedingEnabled = true;

    // Initialize SuperSeeder if not already initialized
    if (_superseeder == null && _metaInfo.pieces != null) {
      _superseeder = SuperSeeder(_metaInfo.pieces!.length);
      _log.info(
          'SuperSeeder initialized for ${_metaInfo.pieces!.length} pieces');
    }

    // Enable superseeding only if we're a seeder
    if (_fileManager != null && _fileManager!.isAllComplete) {
      _superseeder?.enable();
      _log.info('Superseeding enabled (client is a seeder)');
    } else {
      _log.info(
          'Superseeding will be enabled when download completes (client is not yet a seeder)');
    }
  }

  @override
  void disableSuperseeding() {
    if (!_superseedingEnabled) {
      _log.warning('Superseeding is not enabled');
      return;
    }

    _superseedingEnabled = false;
    _superseeder?.disable();
    _log.info('Superseeding disabled');
  }

  @override
  bool get isSuperseedingEnabled => _superseedingEnabled;

  @override
  Future<scrape.ScrapeResult> scrapeTracker([Uri? trackerUrl]) async {
    _scrapeClient ??= scrape.ScrapeClient(
      proxyManager: _proxyManager,
    );

    // Use provided tracker URL or first tracker from torrent
    Uri? url = trackerUrl;
    if (url == null && _metaInfo.announces.isNotEmpty) {
      // Get first tracker
      url = _metaInfo.announces.first;
    }

    if (url == null) {
      return scrape.ScrapeResult(
        trackerUrl: Uri(),
        stats: {},
        error: 'No tracker URL provided and no trackers in torrent',
      );
    }

    // Perform scrape with torrent's info hash
    final infoHash = Uint8List.fromList(_metaInfo.infoHashBuffer);
    return await _scrapeClient!.scrape(url, [infoHash]);
  }
}
