import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../media_range.dart';
import 'watch_party_protocol.dart';

/// Watch Together: keeps playback in step across devices on the same network.
///
/// One device hosts and becomes the clock; the others join with a six-character
/// room code. There is no server and no account — the host runs a small
/// WebSocket server on the LAN, and guests find it by UDP broadcast so the code
/// is the only thing anyone has to type.
///
/// The decisions about *what to do* with an incoming update live in
/// [watch_party_protocol.dart] and are unit-tested there. This file is the I/O.
class WatchPartyService {
  WatchPartyService();

  /// Port the host listens on. Fixed so discovery replies stay small; if it is
  /// busy the host falls back to an ephemeral port and advertises it.
  static const int defaultSyncPort = 47825;

  /// UDP port used to answer "who is hosting room X?".
  static const int discoveryPort = 47826;

  static const String _discoveryQueryPrefix = 'BITPLAYER-WATCH-WHO:';
  static const String _discoveryReplyPrefix = 'BITPLAYER-WATCH-AT:';

  /// Monotonic source for all clock readings. Wall-clock time would jump when
  /// the OS syncs NTP mid-session and desync everyone.
  final Stopwatch _clock = Stopwatch()..start();
  int get nowMs => _clock.elapsedMilliseconds;

  final _events = StreamController<WatchPartyEvent>.broadcast();
  final _status = StreamController<WatchPartyStatus>.broadcast();

  /// Actions the player should apply (seek/play/pause/load).
  Stream<WatchPartyEvent> get events => _events.stream;

  /// Room state for the UI.
  Stream<WatchPartyStatus> get statusStream => _status.stream;

  WatchPartyStatus _currentStatus = const WatchPartyStatus.idle();
  WatchPartyStatus get status => _currentStatus;

  // Host state
  HttpServer? _server;
  RawDatagramSocket? _discoverySocket;
  final List<WebSocket> _guests = [];
  String? _roomCode;
  int _boundPort = defaultSyncPort;

  /// Files the host is streaming, keyed by an unguessable token. Guests that
  /// do not have the file play it from here instead of being stuck (issue #7).
  final Map<String, String> _sharedMedia = {};
  final Map<String, String> _tokensByPath = {};

  // Guest state
  WebSocket? _hostSocket;
  String? _hostEndpoint;
  Timer? _pingTimer;
  final ClockOffsetEstimator _offset = ClockOffsetEstimator();
  PlaybackSnapshot? _lastSnapshot;

  String _displayName = 'Someone';

  bool get isHosting => _server != null;
  bool get isGuest => _hostSocket != null;
  bool get isActive => isHosting || isGuest;
  String? get roomCode => _roomCode;

  /// Port the host is listening on, once [startHosting] has returned.
  int get boundPort => _boundPort;

  /// Round-trip time to the host, for showing connection quality.
  int? get latencyMs => _offset.bestRttMs;

  void _setStatus(WatchPartyStatus status) {
    _currentStatus = status;
    if (!_status.isClosed) _status.add(status);
  }

  /// Writes one frame, swallowing the failure if the peer has already gone.
  ///
  /// Frames cross in flight constantly: a guest fires a ping at the same
  /// moment the host tears the room down, and the reply lands on a closed
  /// sink. That is normal, not an error worth propagating.
  bool _safeSend(WebSocket socket, String frame) {
    try {
      socket.add(frame);
      return true;
    } catch (e) {
      debugPrint('WatchParty send skipped (peer gone): $e');
      return false;
    }
  }

  void _emit(WatchPartyEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  // -------------------------------------------------------------- hosting
  /// Starts hosting and returns the room code to share.
  Future<String> startHosting({required String displayName}) async {
    await leave();
    _displayName = displayName;
    final code = generateRoomCode();
    _roomCode = code;

    try {
      // Deliberately NOT shared: two hosts sharing one port would round-robin
      // incoming guests between them, so a guest could land in the wrong room.
      _server = await HttpServer.bind(InternetAddress.anyIPv4, defaultSyncPort);
      _boundPort = defaultSyncPort;
    } on SocketException {
      // Port busy (usually another host on this machine). Take any free port;
      // discovery advertises whichever one we landed on.
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _boundPort = _server!.port;
    }

    _server!.listen(_onHttpRequest, onError: (Object e) {
      debugPrint('WatchParty host server error: $e');
    });

    await _startDiscoveryResponder();
    _setStatus(WatchPartyStatus(
      role: WatchPartyRole.host,
      roomCode: code,
      peerCount: 0,
      message: 'Waiting for others to join',
    ));
    debugPrint('WatchParty hosting room $code on port $_boundPort');
    return code;
  }

  Future<void> _onHttpRequest(HttpRequest request) async {
    final path = request.uri.path;
    if (path.startsWith('/media/')) {
      await _serveSharedMedia(request, path.substring('/media/'.length));
      return;
    }
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Watch Together endpoint');
      await request.response.close();
      return;
    }
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      _handleGuestSocket(socket);
    } catch (e) {
      debugPrint('WatchParty upgrade failed: $e');
    }
  }

  /// Streams a file the host has explicitly shared for this room.
  ///
  /// Only tokens minted by [shareMedia] resolve, so hosting a room never turns
  /// the device into an open file server.
  Future<void> _serveSharedMedia(HttpRequest request, String token) async {
    final path = _sharedMedia[token];
    if (path == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    await serveFileWithRanges(
      request,
      File(path),
      contentType: mediaContentTypeFor(path),
    );
  }

  /// Host: offer [path] to the room, returning the relative URL for it.
  ///
  /// Returns null when not hosting. Calling it twice for the same file gives
  /// back the same token, so a guest's stream is not broken by a re-publish.
  String? shareMedia(String path) {
    if (!isHosting || path.isEmpty) return null;
    final existing = _tokensByPath[path];
    if (existing != null) return '/media/$existing';

    // The original extension is kept on the token so the guest's player can
    // tell audio from video before a single byte arrives.
    final dot = path.lastIndexOf('.');
    final extension = dot > 0 && path.length - dot <= 6
        ? path.substring(dot).toLowerCase()
        : '';
    final token = '${_mintToken()}$extension';
    _sharedMedia[token] = path;
    _tokensByPath[path] = token;
    return '/media/$token';
  }

  String _mintToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Guest: the absolute URL for the host's stream of [snapshot], if any.
  String? hostStreamUrlFor(PlaybackSnapshot snapshot) {
    final endpoint = _hostEndpoint;
    final source = snapshot.source;
    if (endpoint == null || source == null) return null;
    return source.urlFor(endpoint);
  }

  void _handleGuestSocket(WebSocket socket) {
    var admitted = false;
    var refused = false;
    socket.listen(
      (dynamic raw) {
        // A refused peer usually has frames already in flight (the guest fires
        // its first ping immediately after hello). Writing to the socket we
        // just closed would throw "StreamSink is closed", so stop here.
        if (refused) return;
        if (raw is! String) return;
        final message = WatchPartyMessage.decode(raw);
        if (message == null) return;

        if (!admitted) {
          final reason = rejectionReasonForHello(
              message: message, expectedRoom: _roomCode ?? '');
          if (reason != null) {
            refused = true;
            _safeSend(socket, WatchPartyMessage.deniedMessage(reason).encode());
            socket.close();
            return;
          }
          admitted = true;
          _guests.add(socket);
          // A peer can vanish between the upgrade and the welcome; a failed
          // write must not take down the whole handler.
          final welcomed = _safeSend(
              socket,
              WatchPartyMessage.welcomeMessage(hostName: _displayName)
                  .encode());
          // Send the current state immediately so a late joiner does not sit
          // on a black screen until the next periodic update.
          final snapshot = _lastSnapshot;
          if (welcomed && snapshot != null) {
            _safeSend(
                socket, WatchPartyMessage.stateMessage(snapshot).encode());
          }
          if (!welcomed) _guests.remove(socket);
          _broadcastPeerCount();
          return;
        }

        if (message.type == WatchPartyMessage.ping) {
          final clientClock = message.data['c'];
          if (clientClock is num) {
            _safeSend(
                socket,
                WatchPartyMessage.pongMessage(
                  clientClockMs: clientClock.round(),
                  hostClockMs: nowMs,
                ).encode());
          }
        }
      },
      onDone: () {
        _guests.remove(socket);
        _broadcastPeerCount();
      },
      onError: (Object e) {
        debugPrint('WatchParty guest socket error: $e');
        _guests.remove(socket);
        _broadcastPeerCount();
      },
      cancelOnError: true,
    );
  }

  void _broadcastPeerCount() {
    if (!isHosting) return;
    _setStatus(WatchPartyStatus(
      role: WatchPartyRole.host,
      roomCode: _roomCode,
      peerCount: _guests.length,
      message: _guests.isEmpty
          ? 'Waiting for others to join'
          : '${_guests.length} watching with you',
    ));
  }

  /// Host: publish the current playback state. Safe to call often; it is a
  /// cheap fan-out and guests only act when they are actually out of step.
  void publishState({
    required String mediaKey,
    required Duration position,
    required bool playing,
    String? title,
    String? sourcePath,
  }) {
    if (!isHosting) return;
    final snapshot = PlaybackSnapshot(
      mediaKey: mediaKey,
      position: position,
      playing: playing,
      hostClockMs: nowMs,
      title: title,
      source: sourcePath == null ? null : MediaSource(path: sourcePath),
    );
    _lastSnapshot = snapshot;
    final frame = WatchPartyMessage.stateMessage(snapshot).encode();
    for (final guest in List<WebSocket>.from(_guests)) {
      if (!_safeSend(guest, frame)) _guests.remove(guest);
    }
  }

  // ------------------------------------------------------------ discovery
  Future<void> _startDiscoveryResponder() async {
    try {
      final socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4, discoveryPort,
          reuseAddress: true, reusePort: false);
      socket.broadcastEnabled = true;
      _discoverySocket = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final text = utf8.decode(datagram.data, allowMalformed: true);
        if (!text.startsWith(_discoveryQueryPrefix)) return;
        final wanted = text.substring(_discoveryQueryPrefix.length).trim();
        if (_roomCode == null ||
            wanted.toUpperCase() != _roomCode!.toUpperCase()) {
          return;
        }
        final reply = '$_discoveryReplyPrefix$_boundPort';
        socket.send(utf8.encode(reply), datagram.address, datagram.port);
      });
    } catch (e) {
      // Discovery is a convenience; hosting still works if a guest is given
      // the address directly.
      debugPrint('WatchParty discovery responder unavailable: $e');
    }
  }

  /// Broadcasts for the host of [code] and returns "host:port", or null.
  Future<String?> _findHost(String code,
      {Duration timeout = const Duration(seconds: 4)}) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final completer = Completer<String?>();
      final query = utf8.encode('$_discoveryQueryPrefix$code');

      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket!.receive();
        if (datagram == null) return;
        final text = utf8.decode(datagram.data, allowMalformed: true);
        if (!text.startsWith(_discoveryReplyPrefix)) return;
        final port =
            int.tryParse(text.substring(_discoveryReplyPrefix.length).trim());
        if (port == null) return;
        if (!completer.isCompleted) {
          completer.complete('${datagram.address.address}:$port');
        }
      });

      // Re-broadcast a few times: UDP is lossy, and wifi power saving on
      // phones drops the first packet often enough to matter.
      final ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
        try {
          socket!
              .send(query, InternetAddress('255.255.255.255'), discoveryPort);
        } catch (_) {}
      });
      try {
        socket.send(query, InternetAddress('255.255.255.255'), discoveryPort);
      } catch (_) {}

      final result = await completer.future
          .timeout(timeout, onTimeout: () => null)
          .whenComplete(ticker.cancel);
      return result;
    } catch (e) {
      debugPrint('WatchParty discovery failed: $e');
      return null;
    } finally {
      socket?.close();
    }
  }

  // --------------------------------------------------------------- joining
  /// Joins [rawCode] by finding the host on the local network.
  /// Returns null on success, or a message to show the user.
  Future<String?> join(String rawCode, {required String displayName}) async {
    final code = normaliseRoomCode(rawCode);
    if (!isValidRoomCode(code)) {
      return 'That room code does not look right. It is '
          '$kRoomCodeLength characters, like ${generateRoomCode()}.';
    }

    await leave();
    _displayName = displayName;
    _setStatus(WatchPartyStatus(
      role: WatchPartyRole.connecting,
      roomCode: code,
      message: 'Looking for the room on your network…',
    ));

    final endpoint = await _findHost(code);
    if (endpoint == null) {
      _setStatus(const WatchPartyStatus.idle());
      return 'No room "$code" found on this network. Check the code, and that '
          'both devices are on the same wifi. Some networks block discovery — '
          'you can also join using the host IP address.';
    }
    return joinAt(endpoint, code: code, displayName: displayName);
  }

  /// Joins a host at a known `host:port`, skipping discovery.
  ///
  /// Used as the fallback when a network blocks UDP broadcast (guest wifi and
  /// some mesh routers do), and by the integration tests.
  Future<String?> joinAt(String endpoint,
      {required String code, required String displayName}) async {
    _displayName = displayName;
    try {
      final socket = await WebSocket.connect('ws://$endpoint/')
          .timeout(const Duration(seconds: 8));
      _hostSocket = socket;
      _hostEndpoint = endpoint;
      _roomCode = code;
      _offset.reset();

      socket.add(WatchPartyMessage.helloMessage(room: code, name: displayName)
          .encode());
      socket.listen(_onHostMessage, onDone: _onHostDisconnected,
          onError: (Object e) {
        debugPrint('WatchParty host socket error: $e');
        _onHostDisconnected();
      }, cancelOnError: true);

      // Measure the clock offset promptly, then keep it fresh.
      _sendPing();
      _pingTimer =
          Timer.periodic(const Duration(seconds: 5), (_) => _sendPing());

      _setStatus(WatchPartyStatus(
        role: WatchPartyRole.guest,
        roomCode: code,
        message: 'Connected — syncing',
      ));
      return null;
    } catch (e) {
      debugPrint('WatchParty join failed: $e');
      _setStatus(const WatchPartyStatus.idle());
      return 'Could not connect to the room. It may have just closed.';
    }
  }

  void _sendPing() {
    final socket = _hostSocket;
    if (socket == null) return;
    _safeSend(socket, WatchPartyMessage.pingMessage(nowMs).encode());
  }

  void _onHostMessage(dynamic raw) {
    if (raw is! String) return;
    final message = WatchPartyMessage.decode(raw);
    if (message == null) return;

    switch (message.type) {
      case WatchPartyMessage.pong:
        final sent = message.data['c'];
        final hostClock = message.data['h'];
        if (sent is num && hostClock is num) {
          _offset.addSample(
            sentAtMs: sent.round(),
            hostClockMs: hostClock.round(),
            receivedAtMs: nowMs,
          );
        }
        break;

      case WatchPartyMessage.state:
        final snapshot = PlaybackSnapshot.fromJson(message.data);
        if (snapshot == null) return;
        _lastSnapshot = snapshot;
        // Without a clock estimate the projection would be meaningless, so
        // wait for the first pong rather than seeking to a wrong position.
        if (!_offset.hasEstimate) return;
        _emit(WatchPartyEvent.remoteState(
          snapshot: snapshot,
          hostClockNowMs: _offset.hostClockNow(nowMs),
        ));
        break;

      case WatchPartyMessage.denied:
        final reason = message.data['reason'];
        _emit(WatchPartyEvent.denied(
            reason is String ? reason : 'The host refused the connection.'));
        unawaited(leave());
        break;

      case WatchPartyMessage.bye:
        _emit(const WatchPartyEvent.hostLeft());
        unawaited(leave());
        break;
    }
  }

  void _onHostDisconnected() {
    if (_hostSocket == null) return;
    _emit(const WatchPartyEvent.hostLeft());
    unawaited(leave());
  }

  // ---------------------------------------------------------------- teardown
  Future<void> leave() async {
    _pingTimer?.cancel();
    _pingTimer = null;

    // Snapshot the sockets, then clear every piece of observable state
    // *synchronously*. Callers that react to a hostLeft event check the role
    // immediately; if the reset waited behind these awaits they would still
    // see the old one.
    final host = _hostSocket;
    final guests = List<WebSocket>.from(_guests);
    final server = _server;
    final discovery = _discoverySocket;

    _hostSocket = null;
    _hostEndpoint = null;
    _guests.clear();
    _server = null;
    _discoverySocket = null;
    _roomCode = null;
    _lastSnapshot = null;
    // Shared-media tokens must not outlive the room that minted them.
    _sharedMedia.clear();
    _tokensByPath.clear();
    _offset.reset();
    if (_currentStatus.role != WatchPartyRole.idle) {
      _setStatus(const WatchPartyStatus.idle());
    }

    final bye = WatchPartyMessage.byeMessage().encode();
    for (final socket in [if (host != null) host, ...guests]) {
      _safeSend(socket, bye);
      try {
        await socket.close();
      } catch (_) {}
    }
    try {
      await server?.close(force: true);
    } catch (_) {}
    discovery?.close();
  }

  Future<void> dispose() async {
    await leave();
    await _events.close();
    await _status.close();
  }
}

enum WatchPartyRole { idle, host, guest, connecting }

class WatchPartyStatus {
  const WatchPartyStatus({
    required this.role,
    this.roomCode,
    this.peerCount = 0,
    this.message = '',
  });

  const WatchPartyStatus.idle()
      : role = WatchPartyRole.idle,
        roomCode = null,
        peerCount = 0,
        message = '';

  final WatchPartyRole role;
  final String? roomCode;
  final int peerCount;
  final String message;

  bool get isActive => role != WatchPartyRole.idle;
}

enum WatchPartyEventKind { remoteState, hostLeft, denied }

class WatchPartyEvent {
  const WatchPartyEvent._(this.kind,
      {this.snapshot, this.hostClockNowMs, this.reason});

  const WatchPartyEvent.remoteState({
    required PlaybackSnapshot snapshot,
    required int hostClockNowMs,
  }) : this._(WatchPartyEventKind.remoteState,
            snapshot: snapshot, hostClockNowMs: hostClockNowMs);

  const WatchPartyEvent.hostLeft() : this._(WatchPartyEventKind.hostLeft);

  const WatchPartyEvent.denied(String reason)
      : this._(WatchPartyEventKind.denied, reason: reason);

  final WatchPartyEventKind kind;
  final PlaybackSnapshot? snapshot;
  final int? hostClockNowMs;
  final String? reason;
}
