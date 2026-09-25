import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:crypto/crypto.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:dtorrent_task_v2/src/peer/protocol/peer_events.dart';
import 'package:events_emitter2/events_emitter2.dart';
import 'package:logging/logging.dart';
import 'package:utp_protocol/utp_protocol.dart';

import '../congestion_control.dart';
import '../speed_calculator.dart';
import '../extensions/extended_processor.dart';

const KEEP_ALIVE_MESSAGE = [0, 0, 0, 0];

// [BEP 0003](http://www.bittorrent.org/beps/bep_0003.html) states:
// All later integers sent in the protocol are encoded as four bytes big-endian
const MESSAGE_INTEGER = 4;

// This is the length of the handshake message which consist of
// 20 bytes for the header
const HAND_SHAKE_HEAD = [
  19,
  66,
  105,
  116,
  84,
  111,
  114,
  114,
  101,
  110,
  116,
  32,
  112,
  114,
  111,
  116,
  111,
  99,
  111,
  108
];
// 8 reserved bytes
const RESERVED = [0, 0, 0, 0, 0, 0, 0, 0];
// 20 bytes for the infohash
const INFO_HASH_START = 28;
// 20 bytes for peer id
const PEER_ID_START = 48;

// which totals to: 68
const HAND_SHAKE_MESSAGE_LENGTH = 68;

const ID_CHOKE = 0;
const ID_UNCHOKE = 1;
const ID_INTERESTED = 2;
const ID_NOT_INTERESTED = 3;
const ID_HAVE = 4;
const ID_BITFIELD = 5;
const ID_REQUEST = 6;
const ID_PIECE = 7;
const ID_CANCEL = 8;
const ID_PORT = 9;
const ID_EXTENDED = 20;
// BEP 52 v2 protocol messages
const ID_HASH_REQUEST = 21;
const ID_HASHES = 22;
const ID_HASH_REJECT = 23;

const OP_HAVE_ALL = 0x0e;
const OP_HAVE_NONE = 0x0f;
const OP_SUGGEST_PIECE = 0x0d;
const OP_REJECT_REQUEST = 0x10;
const OP_ALLOW_FAST = 0x11;

/// Maximum message size in bytes (2MB)
///
/// Messages larger than this size will be rejected to prevent buffer overflows
/// and excessive memory usage. This limit applies to both sending and receiving.
const MAX_MESSAGE_SIZE = 1024 * 1024 * 2;

/// Buffer size threshold for warnings (10MB)
///
/// When the total buffer size (cache buffer + incoming data) exceeds this threshold,
/// a warning is logged to help identify potential memory issues or buffer buildup.
const BUFFER_SIZE_WARNING_THRESHOLD = 10 * 1024 * 1024;

/// Maximum signed 32-bit integer value (2^31 - 1)
///
/// Used to prevent integer overflow in buffer offset calculations.
const MAX_INT32 = 0x7FFFFFFF;

enum PeerType { TCP, UTP }

/// 30 Seconds
const DEFAULT_CONNECT_TIMEOUT = 30;

enum PeerSource { tracker, dht, pex, lsd, incoming, manual, holepunch }

abstract class Peer
    with
        EventsEmittable<PeerEvent>,
        ExtendedProcessor,
        CongestionControl,
        SpeedCalculator {
  late final Logger _log = Logger(runtimeType.toString());

  /// Metrics for tracking RangeError patterns (for uTP crash monitoring)
  ///
  /// These metrics help monitor and debug RangeError crashes in uTP protocol,
  /// particularly those related to selective ACK processing and buffer handling.
  ///
  /// Example usage:
  /// ```dart
  /// // Check if any RangeErrors occurred
  /// if (Peer.rangeErrorCount > 0) {
  ///   print('Total RangeErrors: ${Peer.rangeErrorCount}');
  ///   print('uTP RangeErrors: ${Peer.utpRangeErrorCount}');
  ///   print('Errors by reason: ${Peer.rangeErrorByReason}');
  /// }
  ///
  /// // Reset metrics for new test/session
  /// Peer.resetRangeErrorMetrics();
  /// ```
  ///
  /// Error reasons tracked:
  /// - `PROCESS_RECEIVE_DATA`: RangeError in message parsing/receiving
  /// - `VALIDATE_INFO_HASH`: RangeError in infohash validation
  /// - `CONNECT_REMOTE`: RangeError during uTP connection
  /// - `SEND_BYTE_MESSAGE`: RangeError when sending messages
  /// - `UINT8LIST_CONVERSION`: RangeError converting bytes to Uint8List
  /// - `STREAM_ERROR`: RangeError in stream error handler
  static int _rangeErrorCount = 0;
  static int _utpRangeErrorCount = 0;
  static final Map<String, int> _rangeErrorByReason = {};

  /// Total number of RangeErrors recorded across all peers
  static int get rangeErrorCount => _rangeErrorCount;

  /// Number of RangeErrors specific to uTP peers
  static int get utpRangeErrorCount => _utpRangeErrorCount;

  /// Map of error reasons to their occurrence counts
  static Map<String, int> get rangeErrorByReason =>
      Map.unmodifiable(_rangeErrorByReason);

  static void _recordRangeError(String reason, {bool isUtp = false}) {
    _rangeErrorCount++;
    if (isUtp) {
      _utpRangeErrorCount++;
    }
    _rangeErrorByReason[reason] = (_rangeErrorByReason[reason] ?? 0) + 1;
  }

  /// Reset all RangeError metrics
  ///
  /// Useful for starting a new monitoring period or test session.
  static void resetRangeErrorMetrics() {
    _rangeErrorCount = 0;
    _utpRangeErrorCount = 0;
    _rangeErrorByReason.clear();
  }

  /// Countdown time , when peer don't receive or send any message from/to remote ,
  /// this class will invoke close.
  /// Unit: second
  int countdownTime = 150;

  String get id {
    return address.toContactEncodingString();
  }

  /// The total number of pieces of downloaded items
  final int _piecesNum;

  /// Remote Bitfield
  Bitfield? _remoteBitfield;

  /// Whether the peer has been disposed
  bool _disposed = false;

  /// Countdown to close Timer.
  Timer? _countdownTimer;

  /// Whether the other party choke me, the initial default is true
  bool _chokeMe = true;

  /// Did I choke the other party, the default is true
  bool chokeRemote = true;

  /// Whether the other party is interested in my resources, the default is false
  bool _interestedMe = false;

  /// Am I interested in the resources of the other party, the default is false
  bool interestedRemote = false;

  /// Debug use
  // ignore: unused_field
  dynamic _disposeReason;

  /// The address and port of the remote peer
  final CompactAddress address;

  /// Torrent infohash buffer
  final List<int> _infoHashBuffer;

  String? _remotePeerId;

  /// has this peer send handshake message already?
  bool _handShaked = false;

  /// has this peer send local bitfield to remote?
  bool _bitfieldSended = false;

  /// Remote data reception, listening to subscription.
  StreamSubscription<Uint8List>? _streamChunk;

  /// Buffer to obtain data from the channel.
  List<int> _cacheBuffer = [];

  /// The local sends a request buffer. The format is: [index, begin, length].
  final _requestBuffer = <List<int>>[];

  /// The remote sends a request buffer. The format is: [index, begin, length].
  final _remoteRequestBuffer = <List<int>>[];

  /// Max request count in one piple ,5
  static const MAX_REQUEST_COUNT = 5;

  bool remoteEnableFastPeer = false;

  bool localEnableFastPeer = true;

  bool remoteEnableExtended = false;

  bool localEnableExtended = true;

  /// Local Allow Fast pieces.
  final Set<int> _allowFastPieces = <int>{};

  /// Remote Allow Fast pieces.
  final Set<int> _remoteAllowFastPieces = <int>{};

  /// Remote Suggest pieces.
  final Set<int> _remoteSuggestPieces = <int>{};

  final PeerType type;

  final PeerSource source;

  int reqq;

  int? remoteReqq;

  /// Torrent version support (v1, v2, or hybrid)
  /// Used to set handshake reserved bits for v2 support
  TorrentVersion? _torrentVersion;

  /// Set torrent version for this peer connection
  /// This affects handshake reserved bits for v2/hybrid support
  void setTorrentVersion(TorrentVersion version) {
    _torrentVersion = version;
  }

  /// [_id] is used to differentiate between different peers. It is different from
  ///  [_localPeerId], which is the Peer_id in the BitTorrent protocol.
  /// [address] is the remote peer's address and port, and subclasses can use this
  ///  value for remote connections.
  /// [_infoHashBuffer] is the infohash value from the torrent file,
  /// and [_piecesNum] is the total number of pieces in the download project,
  /// which is used to construct the remote `Bitfield` data.
  /// The optional parameter [localEnableFastPeer] is set to `true` by default,
  /// indicating whether local peers can use the
  /// [Fast Extension (BEP 0006)](http://www.bittorrent.org/beps/bep_0006.html).
  /// [localEnableExtended] indicates whether local peers can use the
  /// [Extension Protocol](http://www.bittorrent.org/beps/bep_0010.html).
  Peer(this.address, this._infoHashBuffer, this._piecesNum, this.source,
      {this.type = PeerType.TCP,
      this.localEnableFastPeer = true,
      this.localEnableExtended = true,
      this.reqq = 100}) {
    _remoteBitfield = Bitfield.createEmptyBitfield(_piecesNum);
  }

  factory Peer.newTCPPeer(CompactAddress address, List<int> infoHashBuffer,
      int piecesNum, Socket? socket, PeerSource source,
      {bool enableExtend = true,
      bool enableFast = true,
      ProxyManager? proxyManager}) {
    return _TCPPeer(address, infoHashBuffer, piecesNum, socket, source,
        enableExtend: enableExtend,
        enableFast: enableFast,
        proxyManager: proxyManager);
  }

  factory Peer.newUTPPeer(CompactAddress address, List<int> infoHashBuffer,
      int piecesNum, UTPSocket? socket, PeerSource source,
      {bool enableExtend = true, bool enableFast = true}) {
    return _UTPPeer(address, infoHashBuffer, piecesNum, socket, source,
        enableExtend: enableExtend, enableFast: enableFast);
  }

  /// The remote peer's bitfield.
  Bitfield? get remoteBitfield => _remoteBitfield;

  /// Whether the local bitfield has been sent to the remote peer.
  bool get bitfieldSended => _bitfieldSended;

  bool get isLeecher => !isSeeder;

  /// If it has the complete torrent file, then it is a seeder.
  bool get isSeeder {
    if (_remoteBitfield == null) return false;
    if (_remoteBitfield!.haveAll()) return true;
    return false;
  }

  String? get remotePeerId => _remotePeerId;

  /// Requests received from the remote peer.
  List<List<int>> get remoteRequestBuffer => _remoteRequestBuffer;

  /// Requests sent from the local peer to the remote peer.
  List<List<int>> get requestBuffer => _requestBuffer;

  Set<int> get remoteSuggestPieces => _remoteSuggestPieces;

  /// Remote Allow Fast pieces (pieces that can be downloaded when choked)
  Set<int> get remoteAllowFastPieces => _remoteAllowFastPieces;

  bool get isDisposed => _disposed;

  bool get chokeMe => _chokeMe;

  set chokeMe(bool c) {
    if (c != _chokeMe) {
      _chokeMe = c;
      events.emit(PeerChokeChanged(this, _chokeMe));
    }
  }

  bool? remoteHave(int index) {
    return _remoteBitfield?.getBit(index);
  }

  bool get interestedMe => _interestedMe;

  set interestedMe(bool i) {
    if (i != _interestedMe) {
      _interestedMe = i;
      events.emit(PeerInterestedChanged(this, _interestedMe));
    }
  }

  /// All completed pieces of the remote peer.
  List<int> get remoteCompletePieces {
    if (_remoteBitfield == null) return [];
    return _remoteBitfield!.completedPieces;
  }

  /// Connect remote peer
  Future connect([int timeout = DEFAULT_CONNECT_TIMEOUT]) async {
    _log.fine('Connecting to peer $address (source: $source)');
    try {
      _init();
      var stream = await connectRemote(timeout);
      _log.fine('Connected stream established for peer $address');
      startSpeedCalculator();
      _streamChunk = stream?.listen(_processReceiveData, onDone: () {
        _log.info('Connection is closed $address');
        dispose(BadException('The remote peer closed the connection'));
      }, onError: (e) {
        if (e is RangeError) {
          var reason = 'STREAM_ERROR';
          Peer._recordRangeError(reason, isUtp: type == PeerType.UTP);
          _log.severe(
              'RangeError in peer stream: peer=$address, type=$type, error=${e.message}',
              e);
          dispose('STREAM_RANGE_ERROR');
        } else {
          _log.warning('Error happen: $address', e);
          dispose(e);
        }
      });
      _log.fine('Emitting PeerConnected event for peer $address');
      events.emit(PeerConnected(this));
    } catch (e) {
      if (e is TCPConnectException) return dispose(e);
      return dispose(BadException(e));
    }
  }

  /// Initialize some basic data.
  void _init() {
    /// Initialize data.
    _disposeReason = null;
    _disposed = false;
    _handShaked = false;

    /// Clear the channel data cache.
    _cacheBuffer.clear();

    /// Clear the request cache.
    _requestBuffer.clear();
    _remoteRequestBuffer.clear();

    /// Reset the fast pieces.
    _remoteAllowFastPieces.clear();
    _allowFastPieces.clear();

    /// Reset the suggest pieces.
    _remoteSuggestPieces.clear();

    /// Reset the remote fast extension flag.
    remoteEnableFastPeer = false;
  }

  List<int>? removeRequest(int index, int begin, int length) {
    var request = _removeRequestFromBuffer(index, begin, length);
    return request;
  }

  /// Add a request to the buffer.

  /// This request is an array:
  /// - 0: index
  /// - 1: begin
  /// - 2: length
  /// - 3: send time
  /// - 4: resend times
  bool addRequest(int index, int begin, int length) {
    var maxCount = currentWindow;
    // maxCount = oldCount;
    if (remoteReqq != null) maxCount = min(remoteReqq!, maxCount);
    if (_requestBuffer.length >= maxCount) return false;
    _requestBuffer
        .add([index, begin, length, DateTime.now().microsecondsSinceEpoch, 0]);
    return true;
  }

  bool get isSleeping {
    return _requestBuffer.isEmpty;
  }

  bool get isDownloading {
    return _requestBuffer.isNotEmpty;
  }

  void _processReceiveData(Uint8List data) {
    try {
      // Regardless of what message is received, as long as it is not empty, reset the countdown timer.
      if (data.isNotEmpty) _startToCountdown();

      // Log incoming data details for uTP debugging with buffer size tracking
      if (type == PeerType.UTP && data.isNotEmpty) {
        var totalBufferSize = _cacheBuffer.length + data.length;
        _log.fine(
            'uTP received data: peer=$address, dataLength=${data.length}, '
            'cacheBufferLength=${_cacheBuffer.length}, totalBufferSize=$totalBufferSize');

        // Warn if buffer is getting too large (potential memory issue)
        if (totalBufferSize > BUFFER_SIZE_WARNING_THRESHOLD) {
          _log.warning(
              'uTP buffer size warning: peer=$address, totalBufferSize=$totalBufferSize bytes');
        }
      }

      // Accept data sent by the remote peer and buffer it in one place.
      _cacheBuffer.addAll(data);

      if (_cacheBuffer.isEmpty) return;
      // Check if it's a handshake header.
      if (_cacheBuffer[0] == 19 &&
          _cacheBuffer.length >= HAND_SHAKE_MESSAGE_LENGTH) {
        if (_isHandShakeHead(_cacheBuffer)) {
          if (_validateInfoHash(_cacheBuffer)) {
            var handshakeBuffer = Uint8List(HAND_SHAKE_MESSAGE_LENGTH);
            handshakeBuffer.setRange(
                0, HAND_SHAKE_MESSAGE_LENGTH, _cacheBuffer);
            // clear the buffer to only the handshake
            _cacheBuffer = _cacheBuffer.sublist(HAND_SHAKE_MESSAGE_LENGTH);
            Timer.run(() => _processHandShake(handshakeBuffer));
            if (_cacheBuffer.isNotEmpty) {
              Timer.run(() => _processReceiveData(Uint8List(0)));
            }
            return;
          } else {
            // If infohash buffer is incorrect , dispose this peer
            dispose('Infohash is incorrect');
            return;
          }
        }
      }
      if (_cacheBuffer.length >= MESSAGE_INTEGER) {
        var start = 0;
        var lengthBuffer = Uint8List(MESSAGE_INTEGER);

        // Validate buffer bounds before setRange
        if (start + MESSAGE_INTEGER > _cacheBuffer.length) {
          _log.warning(
              'Invalid buffer bounds: start=$start, bufferLength=${_cacheBuffer.length}, peer=$address');
          return;
        }

        lengthBuffer.setRange(0, MESSAGE_INTEGER, _cacheBuffer, start);
        var length = ByteData.view(lengthBuffer.buffer).getInt32(0, Endian.big);

        // Log message parsing details for uTP debugging
        if (type == PeerType.UTP) {
          _log.fine(
              'uTP parsing message: peer=$address, start=$start, length=$length, bufferLength=${_cacheBuffer.length}');
        }

        // Validate length value - protect against negative or extremely large values
        // Also protect against potential integer overflow in calculations
        if (length < 0 || length > MAX_MESSAGE_SIZE) {
          _log.warning(
              'Invalid message length: $length, peer=$address, bufferLength=${_cacheBuffer.length}, type=$type');
          dispose('Invalid message length: $length');
          return;
        }

        // Additional validation: check if length would cause overflow in subsequent calculations
        if (start + MESSAGE_INTEGER + length > MAX_INT32) {
          _log.warning(
              'Message length would cause integer overflow: start=$start, length=$length, peer=$address');
          dispose('Message length overflow: $length');
          return;
        }

        List<Uint8List>? piecesMessage;
        List<Uint8List>? haveMessages;
        while (_cacheBuffer.length - start - MESSAGE_INTEGER >= length) {
          if (length == 0) {
            // keep alive
            Timer.run(() => _processMessage(null, null));
          } else {
            // Validate bounds before accessing message ID
            if (start + MESSAGE_INTEGER >= _cacheBuffer.length) {
              _log.warning(
                  'Buffer bounds exceeded when reading message ID: start=$start, bufferLength=${_cacheBuffer.length}, peer=$address');
              break;
            }

            // skip the message length to read the id
            // the id is a single byte
            var id = _cacheBuffer[start + MESSAGE_INTEGER];

            // Messages without payload (choke, unchoke, interested, not interested) have length = 1
            // Messages with payload have length > 1
            // Validate message buffer size before creating
            if (length < 1) {
              _log.warning(
                  'Invalid message length: length=$length, peer=$address');
              break;
            }

            // For messages with payload (length > 1), validate bounds
            Uint8List? messageBuffer;
            if (length > 1) {
              // Validate bounds before setRange for message buffer
              var messageStart = start + MESSAGE_INTEGER + 1;
              var messageEnd = messageStart + (length - 1);
              if (messageEnd > _cacheBuffer.length) {
                _log.warning(
                    'Message buffer bounds exceeded: messageEnd=$messageEnd, bufferLength=${_cacheBuffer.length}, length=$length, start=$start, peer=$address');
                break;
              }

              // the message type id is not needed anymore
              messageBuffer = Uint8List(length - 1);

              messageBuffer.setRange(
                0,
                messageBuffer.length,
                _cacheBuffer,
                messageStart,
              );
            } else {
              // Message without payload (length = 1), messageBuffer is null
              messageBuffer = null;
            }

            switch (id) {
              case ID_PIECE:
                if (messageBuffer != null) {
                  piecesMessage ??= <Uint8List>[];
                  piecesMessage.add(messageBuffer);
                }
                break;
              case ID_HAVE:
                if (messageBuffer != null) {
                  haveMessages ??= <Uint8List>[];
                  haveMessages.add(messageBuffer);
                }
                break;
              default:
                Timer.run(() => _processMessage(id, messageBuffer));
            }
          }
          // set to the start of the next message
          start += (MESSAGE_INTEGER + length);
          if (_cacheBuffer.length - start < MESSAGE_INTEGER) break;

          // Validate bounds before reading next message length
          if (start + MESSAGE_INTEGER > _cacheBuffer.length) {
            _log.warning(
                'Buffer bounds exceeded when reading next message: start=$start, bufferLength=${_cacheBuffer.length}, peer=$address');
            break;
          }

          lengthBuffer.setRange(0, MESSAGE_INTEGER, _cacheBuffer, start);
          var nextLength =
              ByteData.view(lengthBuffer.buffer).getInt32(0, Endian.big);

          // Validate next length value
          if (nextLength < 0 || nextLength > MAX_MESSAGE_SIZE) {
            _log.warning(
                'Invalid next message length: $nextLength, peer=$address');
            break;
          }

          length = nextLength;
        }
        if (piecesMessage != null && piecesMessage.isNotEmpty) {
          // we shoud validate that the subpiece length is valid/same as what we requested
          Timer.run(() => _processReceivePieces(piecesMessage!));
        }
        if (haveMessages != null && haveMessages.isNotEmpty) {
          Timer.run(() => _processHave(haveMessages!));
        }
        if (start != 0 && start < _cacheBuffer.length) {
          _cacheBuffer = _cacheBuffer.sublist(start);
        } else if (start >= _cacheBuffer.length) {
          // If we processed all data, clear the buffer
          _cacheBuffer.clear();
        }
      }
    } on RangeError catch (e, stackTrace) {
      var reason = 'PROCESS_RECEIVE_DATA';
      Peer._recordRangeError(reason, isUtp: type == PeerType.UTP);
      _log.severe(
          'RangeError in _processReceiveData: peer=$address, type=$type, '
          'bufferLength=${_cacheBuffer.length}, dataLength=${data.length}, '
          'error=${e.message}',
          e,
          stackTrace);
      dispose('UTP_RANGE_ERROR');
    } catch (e, stackTrace) {
      _log.severe('Error in _processReceiveData: peer=$address', e, stackTrace);
      dispose('PROCESS_DATA_ERROR');
    }
  }

  bool _isHandShakeHead(List<int> buffer) {
    if (buffer.length < HAND_SHAKE_MESSAGE_LENGTH) return false;
    for (var i = 0; i < HAND_SHAKE_HEAD.length; i++) {
      if (buffer[i] != HAND_SHAKE_HEAD[i]) return false;
    }
    return true;
  }

  bool _validateInfoHash(List<int> buffer) {
    try {
      // Validate buffer has enough length before accessing
      if (buffer.length < PEER_ID_START) {
        _log.warning(
            'Buffer too short for infohash validation: length=${buffer.length}, required=$PEER_ID_START, peer=$address');
        return false;
      }

      // Standard handshake always uses 20 bytes for info hash (v1)
      // v2 info hash (32 bytes) is communicated via Extension Protocol (BEP 10)
      // For hybrid torrents, v1 info hash is used in handshake
      var expectedInfoHashLength =
          PEER_ID_START - INFO_HASH_START; // Always 20 bytes

      // Support both v1 (20 bytes) and v2 (32 bytes) info hash buffers
      // But in handshake, we only validate the first 20 bytes
      if (_infoHashBuffer.length < expectedInfoHashLength) {
        _log.warning(
            'InfoHash buffer too short: length=${_infoHashBuffer.length}, required=$expectedInfoHashLength, peer=$address');
        return false;
      }

      // Validate first 20 bytes (standard handshake format)
      for (var i = INFO_HASH_START; i < PEER_ID_START; i++) {
        if (buffer[i] != _infoHashBuffer[i - INFO_HASH_START]) return false;
      }
      return true;
    } on RangeError catch (e, stackTrace) {
      var reason = 'VALIDATE_INFO_HASH';
      Peer._recordRangeError(reason, isUtp: type == PeerType.UTP);
      _log.severe(
          'RangeError in _validateInfoHash: peer=$address, type=$type, bufferLength=${buffer.length}, error=${e.message}',
          e,
          stackTrace);
      return false;
    }
  }

  void _processMessage(int? id, Uint8List? message) {
    if (id == null) {
      _log.fine('process keep alive $address');
      events.emit(PeerKeepAlive(this));
      return;
    } else {
      switch (id) {
        case ID_CHOKE:
          _log.fine('remote choke me : $address');
          chokeMe = true; // choke message
          return;
        case ID_UNCHOKE:
          _log.fine('remote unchoke me : $address');
          chokeMe = false; // unchoke message
          return;
        case ID_INTERESTED:
          _log.fine('remote interested me : $address');
          interestedMe = true;
          return; // interested message
        case ID_NOT_INTERESTED:
          _log.fine('remote not interested me : $address');
          interestedMe = false;
          return; // not interested message
        // case ID_HAVE:
        //   _log('process have from : $address');
        //   var index = ByteData.view(message.buffer).getUint32(0);
        //   _processHave(index);
        //   return; // have message
        case ID_BITFIELD:
          // log('process bitfield from $address');
          if (message != null) initRemoteBitfield(message);
          return; // bitfield message
        case ID_REQUEST:
          _log.fine('process request from $address');
          if (message != null) _processRemoteRequest(message);
          return; // request message
        // case ID_PIECE:
        //   _log('process pieces : $address');
        //   _processReceivePiece(message);
        //   return; // pieces message
        case ID_CANCEL:
          _log.fine('process cancel : $address');
          if (message != null) _processCancel(message);
          return; // cancel message
        case ID_PORT:
          _log.fine('process port : $address');
          if (message != null) {
            var port = ByteData.view(message.buffer).getUint16(0);
            _processPortChange(port);
          }
          return; // port message
        case OP_HAVE_ALL:
          _log.fine('process have all : $address');
          _processHaveAll();
          return;
        case OP_HAVE_NONE:
          _log.fine('process have none : $address');
          _processHaveNone();
          return;
        case OP_SUGGEST_PIECE:
          _log.fine('process suggest pieces : $address');
          if (message != null) _processSuggestPiece(message);
          return;
        case OP_REJECT_REQUEST:
          _log.fine('process reject request : $address');
          if (message != null) _processRejectRequest(message);
          return;
        case OP_ALLOW_FAST:
          _log.fine('process allow fast : $address');
          if (message != null) _processAllowFast(message);
          return;
        case ID_EXTENDED:
          if (message != null) {
            var extensionId = message[0];
            message = message.sublist(1);
            processExtendMessage(extensionId, message);
          }
          return;
        case ID_HASH_REQUEST:
          _log.fine('process hash request from $address');
          if (message != null) _processHashRequest(message);
          return;
        case ID_HASHES:
          _log.fine('process hashes from $address');
          if (message != null) _processHashes(message);
          return;
        case ID_HASH_REJECT:
          _log.fine('process hash reject from $address');
          if (message != null) _processHashReject(message);
          return;
      }
    }
    _log.warning('Cannot process the message', 'Unknown message : $message');
  }

  /// Remove a request from the request buffer.
  ///
  /// This method is called whenever a piece response is received or a request times out.
  List<int>? _removeRequestFromBuffer(int index, int begin, int length) {
    var i = _findRequestIndexFromBuffer(index, begin, length);
    if (i != -1) {
      return _requestBuffer.removeAt(i);
    }
    return null;
  }

  int _findRequestIndexFromBuffer(int index, int begin, int length) {
    for (var i = 0; i < _requestBuffer.length; i++) {
      var r = _requestBuffer[i];
      if (r[0] == index && r[1] == begin) {
        return i;
      }
    }
    return -1;
  }

  @override
  void processExtendHandshake(data) {
    if (data['reqq'] != null && data['reqq'] is int) {
      remoteReqq = data['reqq'];
    }
    super.processExtendHandshake(data);
  }

  void sendExtendMessage(String name, List<int> data) {
    var id = getExtendedEventId(name);
    if (id != null) {
      var message = <int>[];
      message.add(id);
      message.addAll(data);
      sendMessage(ID_EXTENDED, message);
    }
  }

  void _processCancel(Uint8List message) {
    var view = ByteData.view(message.buffer);
    var index = view.getUint32(0);
    var begin = view.getUint32(4);
    var length = view.getUint32(8);
    int? requestIndex;
    for (var i = 0; i < _remoteRequestBuffer.length; i++) {
      var r = _remoteRequestBuffer[i];
      if (r[0] == index && r[1] == begin) {
        requestIndex = i;
        break;
      }
    }
    if (requestIndex != null) {
      _remoteRequestBuffer.removeAt(requestIndex);
      events.emit(PeerCancelEvent(this, index, begin, length));
    }
  }

  void _processPortChange(int port) {
    if (address.port == port) return;
    events.emit(PeerPortChanged(this, port));
  }

  /// Process Have All message (BEP 6)
  ///
  /// According to BEP 6, Have All completely replaces the bitfield.
  /// All pieces are marked as available, making the peer a seeder.
  void _processHaveAll() {
    if (!remoteEnableFastPeer) {
      // Per [BEP 0006](http://www.bittorrent.org/beps/bep_0006.html):
      // "When the fast extension is disabled, if a peer receives a Have All message, the peer MUST close the connection."
      dispose('Remote disabled fast extension but receive \'have all\'');
      return;
    }

    // Create a new bitfield with all pieces set (replaces existing bitfield)
    _remoteBitfield = Bitfield.createEmptyBitfield(_piecesNum);
    for (var i = 0; i < _remoteBitfield!.buffer.length - 1; i++) {
      _remoteBitfield!.buffer[i] = 255;
    }
    // Set remaining bits in the last byte
    var lastByteIndex = _remoteBitfield!.buffer.length - 1;
    var startIndex = lastByteIndex * 8;
    for (var i = startIndex; i < _remoteBitfield!.piecesNum; i++) {
      _remoteBitfield!.setBit(i, true);
    }

    _log.fine(
        'Peer $address sent HAVE ALL - bitfield completely replaced, peer is now a seeder!');
    events.emit(PeerHaveAll(this));
  }

  /// Process Have None message (BEP 6)
  ///
  /// According to BEP 6, Have None completely replaces the bitfield.
  /// All pieces are marked as unavailable (empty bitfield).
  void _processHaveNone() {
    if (!remoteEnableFastPeer) {
      // Per [BEP 0006](http://www.bittorrent.org/beps/bep_0006.html):
      // "When the fast extension is disabled, if a peer receives a Have None message, the peer MUST close the connection."
      dispose('Remote disabled fast extension but receive \'have none\'');
      return;
    }

    // Create a new empty bitfield (replaces existing bitfield)
    _remoteBitfield = Bitfield.createEmptyBitfield(_piecesNum);
    _log.fine(
        'Peer $address sent HAVE NONE - bitfield completely replaced, peer has no pieces');
    events.emit(PeerHaveNone(this));
  }

  ///
  /// When the fast extension is disabled, if a peer receives a Suggest Piece message,
  /// the peer MUST close the connection.
  void _processSuggestPiece(Uint8List message) {
    if (!remoteEnableFastPeer) {
      // Per [BEP 0006](http://www.bittorrent.org/beps/bep_0006.html):
      // "When the fast extension is disabled, if a peer receives a Suggest Piece message, the peer MUST close the connection."
      dispose('Remote disabled fast extension but receive \'suggest piece\'');
      return;
    }
    var view = ByteData.view(message.buffer);
    var index = view.getUint32(0);
    if (_remoteSuggestPieces.add(index)) {
      events.emit(PeerSuggestPiece(this, index));
    }
  }

  void _processRejectRequest(Uint8List message) {
    if (!remoteEnableFastPeer) {
      // Per [BEP 0006](http://www.bittorrent.org/beps/bep_0006.html):
      // "When the fast extension is disabled, if a peer receives a Reject Request message, the peer MUST close the connection."
      // TODO: Is this correct? or should we close the connection when the "local peer" has the extension disabled?
      dispose('Remote disabled fast extension but receive \'reject request\'');
      return;
    }

    var view = ByteData.view(message.buffer);
    var index = view.getUint32(0);
    var begin = view.getUint32(4);
    var length = view.getUint32(8);
    if (removeRequest(index, begin, length) != null) {
      startRequestDataTimeout();
      events.emit(PeerRejectEvent(this, index, begin, length));
    } else {
      // It's possible that the peer was deleted, but the reject message arrived too late.
      // dispose('Never send request ($index,$begin) but receive a rejection');
      return;
    }
  }

  void _processAllowFast(Uint8List message) {
    if (!remoteEnableFastPeer) {
      // Per [BEP 0006](http://www.bittorrent.org/beps/bep_0006.html):
      // "When the fast extension is disabled, if a peer receives an Allow Fast message, the peer MUST close the connection."
      // TODO: Is this correct? or should we close the connection when the "local peer" has the extension disabled?
      dispose('Remote disabled fast extension but receive \'allow fast\'');
      return;
    }
    var view = ByteData.view(message.buffer);
    var index = view.getUint32(0);
    if (_remoteAllowFastPieces.add(index)) {
      events.emit(PeerAllowFast(this, index));
    }
  }

  /// Process hash request message (BEP 52)
  ///
  /// Hash request contains: pieces root (32 bytes), base layer (1 byte),
  /// index (4 bytes), length (4 bytes), proof layers (1 byte)
  void _processHashRequest(Uint8List message) {
    // Minimum size: 32 (pieces root) + 1 (base layer) + 4 (index) + 4 (length) + 1 (proof layers) = 42
    if (message.length < 42) {
      _log.warning('Hash request message too short: ${message.length} bytes');
      return;
    }

    try {
      var offset = 0;
      var piecesRoot = message.sublist(offset, offset + 32);
      offset += 32;
      var baseLayer = message[offset];
      offset += 1;
      var view = ByteData.view(message.buffer, offset);
      var index = view.getUint32(0, Endian.big);
      offset += 4;
      var length = view.getUint32(4, Endian.big);
      offset += 4;
      var proofLayers = message[offset];

      _log.fine(
          'Hash request: piecesRoot=${_bytesToHex(piecesRoot)}, baseLayer=$baseLayer, index=$index, length=$length, proofLayers=$proofLayers');

      // Emit event for handling by task/manager
      events.emit(PeerHashRequestEvent(
          this, piecesRoot, baseLayer, index, length, proofLayers));
    } catch (e, stackTrace) {
      _log.warning('Failed to process hash request', e, stackTrace);
    }
  }

  /// Process hashes message (BEP 52)
  ///
  /// Hashes message contains: pieces root (32 bytes), base layer (1 byte),
  /// index (4 bytes), length (4 bytes), proof layers (1 byte), hashes (variable)
  void _processHashes(Uint8List message) {
    // Minimum size: 42 bytes (same as hash request) + at least some hashes
    if (message.length < 42) {
      _log.warning('Hashes message too short: ${message.length} bytes');
      return;
    }

    try {
      var offset = 0;
      var piecesRoot = message.sublist(offset, offset + 32);
      offset += 32;
      var baseLayer = message[offset];
      offset += 1;
      var view = ByteData.view(message.buffer, offset);
      var index = view.getUint32(0, Endian.big);
      offset += 4;
      var length = view.getUint32(4, Endian.big);
      offset += 4;
      var proofLayers = message[offset];
      offset += 1;
      var hashes = message.sublist(offset);

      _log.fine(
          'Hashes: piecesRoot=${_bytesToHex(piecesRoot)}, baseLayer=$baseLayer, index=$index, length=$length, proofLayers=$proofLayers, hashesLength=${hashes.length}');

      // Emit event for handling by task/manager
      events.emit(PeerHashesEvent(
          this, piecesRoot, baseLayer, index, length, proofLayers, hashes));
    } catch (e, stackTrace) {
      _log.warning('Failed to process hashes', e, stackTrace);
    }
  }

  /// Process hash reject message (BEP 52)
  ///
  /// Hash reject has the same format as hash request
  void _processHashReject(Uint8List message) {
    // Same format as hash request
    if (message.length < 42) {
      _log.warning('Hash reject message too short: ${message.length} bytes');
      return;
    }

    try {
      var offset = 0;
      var piecesRoot = message.sublist(offset, offset + 32);
      offset += 32;
      var baseLayer = message[offset];
      offset += 1;
      var view = ByteData.view(message.buffer, offset);
      var index = view.getUint32(0, Endian.big);
      offset += 4;
      var length = view.getUint32(4, Endian.big);
      offset += 4;
      var proofLayers = message[offset];

      _log.fine(
          'Hash reject: piecesRoot=${_bytesToHex(piecesRoot)}, baseLayer=$baseLayer, index=$index, length=$length, proofLayers=$proofLayers');

      // Emit event for handling by task/manager
      events.emit(PeerHashRejectEvent(
          this, piecesRoot, baseLayer, index, length, proofLayers));
    } catch (e, stackTrace) {
      _log.warning('Failed to process hash reject', e, stackTrace);
    }
  }

  /// Helper to convert bytes to hex string
  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// When the fast extension is enabled:
  ///
  /// - If a peer receives a request from a peer its choking, the peer receiving the
  /// request SHOULD send a reject unless the piece is in the allowed fast set.
  /// - If a peer receives an excessive number of requests from a peer it is choking,
  /// the peer receiving the requests MAY close the connection rather than reject the request.
  /// However, consider that it can take several seconds for buffers to drain and messages to propagate once a peer is choked.
  void _processRemoteRequest(Uint8List message) {
    if (_remoteRequestBuffer.length > reqq) {
      _log.warning('Request Error:', 'Too many requests from $address');
      dispose(BadException('Too many requests from $address'));
      return;
    }
    var view = ByteData.view(message.buffer);
    var index = view.getUint32(0);
    var begin = view.getUint32(4);
    var length = view.getUint32(8);
    if (length > MAX_REQUEST_LENGTH) {
      _log.warning('TOO LARGE BLOCK', 'BLOCK $length');
      dispose(BadException(
          '$address : request block length larger than limit : $length > $MAX_REQUEST_LENGTH'));
      return;
    }
    if (chokeRemote) {
      if (_allowFastPieces.contains(index)) {
        // Piece is in allowed fast set, accept the request even when choked
        _remoteRequestBuffer.add([index, begin, length]);
        events.emit(PeerRequestEvent(this, index, begin, length));
        return;
      } else {
        // Per BEP 6: When choked, we SHOULD send reject request if fast extension is enabled
        // This helps the remote peer understand that the request was rejected
        if (remoteEnableFastPeer && localEnableFastPeer) {
          sendRejectRequest(index, begin, length);
        }
        // Don't add to request buffer - we're choking and rejecting
        return;
      }
    }

    _remoteRequestBuffer.add([index, begin, length]);
    // TODO Implement speed limit here!
    events.emit(PeerRequestEvent(this, index, begin, length));
  }

  /// Handle the received PIECE messages.
  ///
  /// Unlike other message types, PIECE messages are processed in batches.
  ///
  /// Per BEP 6 and security best practices: if we receive a piece without
  /// a corresponding request, we should close the connection as this may
  /// indicate a protocol violation or attack.
  void _processReceivePieces(List<Uint8List> messages) {
    var requests = <List<int>>[];
    for (var message in messages) {
      // MESSAGE_INTEGER * 2 for index + begin
      var dataHead = Uint8List(MESSAGE_INTEGER * 2);
      dataHead.setRange(0, MESSAGE_INTEGER * 2, message);
      var view = ByteData.view(dataHead.buffer);
      var index = view.getUint32(0, Endian.big);
      var begin = view.getUint32(4, Endian.big);
      var blockLength = message.length - MESSAGE_INTEGER * 2;
      var request = removeRequest(index, begin, blockLength);

      /// Per BEP 6: Receiving a piece without a corresponding request is a protocol violation.
      /// Close the connection to prevent potential attacks or protocol errors.
      if (request == null) {
        _log.warning(
            'Received piece ($index, $begin, $blockLength) without corresponding request from $address - closing connection');
        dispose(BadException(
            'Received piece without request: index=$index, begin=$begin, length=$blockLength'));
        return;
      }
      var block = Uint8List(blockLength);
      block.setRange(0, blockLength, message, MESSAGE_INTEGER * 2);
      requests.add(request);
      _log.fine(
          'Received request for Piece ($index, $begin) content, downloaded $downloaded bytes from the current Peer $type $address');
      events.emit(PeerPieceEvent(this, index, begin, block));
    }
    messages.clear();
    ackRequest(requests);
    updateDownload(requests);
    startRequestDataTimeout();
  }

  void _processHave(List<Uint8List> messages) {
    var indices = <int>[];
    for (var message in messages) {
      var index = ByteData.view(message.buffer).getUint32(0);
      indices.add(index);
      updateRemoteBitfield(index, true);
    }
    events.emit(PeerHaveEvent(this, indices));
  }

  /// Update the remote peer's bitfield.
  void updateRemoteBitfield(int index, bool have) {
    _remoteBitfield?.setBit(index, have);
    if (isSeeder) {
      _log.fine('Peer $address became a seeder after HAVE!');
    }
  }

  void initRemoteBitfield(Uint8List bitfield) {
    _remoteBitfield = Bitfield(_piecesNum, bitfield);
    // Bitfield.copyFrom(_piecesNum, bitfield, 1);
    if (isSeeder) {
      _log.fine('Peer $address is a seeder, ');
    } else {
      _log.fine('Peer $address is NOT a seeder.');
    }
    events.emit(PeerBitfieldEvent(this, _remoteBitfield));
  }

  void _processHandShake(List<int> data) {
    _remotePeerId = _parseRemotePeerId(data);
    var reserved = data.getRange(HAND_SHAKE_HEAD.length, INFO_HASH_START);
    var fast = reserved.elementAt(7) & 0x04;
    remoteEnableFastPeer = (fast == 0x04);
    var extended = reserved.elementAt(5);
    remoteEnableExtended = ((extended & 0x10) == 0x10);
    // BEP 52: Check 4th bit (0x10) in reserved[7] for v2 support
    var v2Support = reserved.elementAt(7) & 0x10;
    if (v2Support == 0x10) {
      _log.fine('Remote peer supports v2 protocol');
      // TODO: Handle v2 info hash upgrade if we're in hybrid mode
    }

    // Generate and send Allowed Fast set if both peers support Fast Extension
    if (remoteEnableFastPeer && localEnableFastPeer) {
      _generateAndSendAllowedFastSet();
    }

    _sendExtendedHandshake();
    events.emit(PeerHandshakeEvent(this, _remotePeerId!, data));
  }

  void _sendExtendedHandshake() async {
    if (localEnableExtended && remoteEnableExtended) {
      var m = await _createExtendedHandshakeMessage();
      sendMessage(ID_EXTENDED, m);
    }
  }

  String _parseRemotePeerId(List<int> data) {
    return String.fromCharCodes(
        data.sublist(PEER_ID_START, HAND_SHAKE_MESSAGE_LENGTH));
  }

  /// Connect remote peer and return a [Stream] future
  ///
  /// [timeout] default value is 30 seconds
  /// Different type peer use different protocol , such as TCP,uTP,
  /// so this method should be implemented by sub-class
  Future<Stream<Uint8List>?> connectRemote(int timeout);

  /// Send message to remote
  ///
  /// this method will transform the [message] and id to be the peer protocol message bytes
  void sendMessage(int? id, [List<int>? message]) {
    if (isDisposed) return;
    if (id == null) {
      // it's keep alive
      sendByteMessage(KEEP_ALIVE_MESSAGE);
      _startToCountdown();
      return;
    }
    var m = _createByteMessage(id, message);
    sendByteMessage(m);
    _startToCountdown();
  }

  Uint8List _createByteMessage(int id, List<int>? message) {
    var length = 0;
    if (message != null) length = message.length;
    length = length + 1;
    var datas = Uint8List(length + MESSAGE_INTEGER);
    var head = Uint8List(MESSAGE_INTEGER);
    var view1 = ByteData.view(head.buffer);
    view1.setUint32(0, length, Endian.big);
    datas.setRange(0, head.length, head);
    datas[4] = id;
    if (message != null && message.isNotEmpty) {
      datas.setRange(5, 5 + message.length, message);
    }
    return datas;
  }

  /// Send the message buffer to remote
  ///
  /// See : [Peer protocol message](https://wiki.theory.org/BitTorrentSpecification#Messages)
  void sendByteMessage(List<int> bytes);

  /// Send a handshake message.
  ///
  /// After sending the handshake message, this method will also proactively send the bitfield and have messages to the remote peer.
  /// For v2/hybrid torrents, uses v1 info hash (first 20 bytes) in handshake for compatibility.
  /// Sets 4th bit (0x10) in reserved[7] for hybrid/v2 torrents to indicate v2 support (BEP 52).
  void sendHandShake(String localPeerId) {
    if (_handShaked) return;
    var message = <int>[];
    message.addAll(HAND_SHAKE_HEAD);
    var reserved = List<int>.from(RESERVED);
    if (localEnableFastPeer) {
      reserved[7] |= 0x04;
    }
    if (localEnableExtended) {
      reserved[5] |= 0x10;
    }
    // BEP 52: Set 4th bit (0x10) in reserved[7] for hybrid/v2 torrents
    // This indicates that we support v2 protocol
    if (_torrentVersion == TorrentVersion.v2 ||
        _torrentVersion == TorrentVersion.hybrid) {
      reserved[7] |= 0x10;
      _log.fine(
          'Setting v2 support bit in handshake for version: $_torrentVersion');
    }
    message.addAll(reserved);
    // Standard handshake always uses 20 bytes for info hash
    // For v2/hybrid torrents, use v1 info hash (first 20 bytes) for compatibility
    var handshakeInfoHash = _infoHashBuffer.length >= 20
        ? _infoHashBuffer.sublist(0, 20)
        : _infoHashBuffer;
    message.addAll(handshakeInfoHash);
    message.addAll(utf8.encode(localPeerId));
    sendByteMessage(message);
    _startToCountdown();
    _handShaked = true;
  }

  Future<List<int>> _createExtendedHandshakeMessage() async {
    var message = <int>[];
    message.add(0);
    var d = <String, dynamic>{};
    d['yourip'] = address.address.rawAddress;
    var version = await getTorrentTaskVersion();
    version ??= '0.0.0';
    d['v'] = 'Dart BT v$version';
    d['m'] = localExtended;
    d['reqq'] = reqq;
    var m = encode(d);
    message.addAll(m);
    return message;
  }

  /// `keep-alive: <len=0000>`
  ///
  /// The `keep-alive` message is a message with zero bytes, specified with the length prefix set to zero.
  /// There is no message ID and no payload. Peers may close a connection if they receive no messages
  /// (keep-alive or any other message) for a certain period of time, so a keep-alive message must be
  /// sent to maintain the connection alive if no command have been sent for a given amount of time.
  /// This amount of time is generally two minutes.
  void sendKeepAlive() {
    sendMessage(null);
  }

  /// `piece: <len=0009+X><id=7><index><begin><block>`
  ///
  /// The `piece` message is variable length, where X is the length of the block. The payload contains the following information:
  ///
  /// - index: integer specifying the zero-based piece index
  /// - begin: integer specifying the zero-based byte offset within the piece
  /// - block: block of data, which is a subset of the piece specified by index.
  bool sendPiece(int index, int begin, List<int> block) {
    if (chokeRemote) {
      if (!remoteEnableFastPeer || !_allowFastPieces.contains(index)) {
        return false;
      }
    }
    int? requestIndex;
    for (var i = 0; i < _remoteRequestBuffer.length; i++) {
      var r = _remoteRequestBuffer[i];
      if (r[0] == index && r[1] == begin) {
        requestIndex = i;
        break;
      }
    }
    if (requestIndex == null) {
      return false;
    }
    _remoteRequestBuffer.removeAt(requestIndex);
    var bytes = <int>[];
    var messageHead = Uint8List(8);
    var view = ByteData.view(messageHead.buffer);
    view.setUint32(0, index, Endian.big);
    view.setUint32(4, begin, Endian.big);
    bytes.addAll(messageHead);
    bytes.addAll(block);
    sendMessage(ID_PIECE, bytes);
    updateUpload(bytes.length);
    return true;
  }

  @override
  void timeOutErrorHappen() {
    dispose('BADTIMEOUT');
  }

  /// `request: <len=0013><id=6><index><begin><length>`
  ///
  /// The `request` message is fixed length, and is used to request a block.
  /// The payload contains the following information:
  ///
  /// - [index]: integer specifying the zero-based piece index
  /// - [begin]: integer specifying the zero-based byte offset within the piece
  /// - [length]: integer specifying the requested length.
  /// - [timeout]: when send request to remote , after [timeout] of not getting response,
  /// it will fire [requestTimeout] event
  bool sendRequest(int index, int begin,
      [int length = DEFAULT_REQUEST_LENGTH]) {
    if (_chokeMe) {
      _log.fine(
          'Peer $address is choking me, cannot send request for Piece ($index, $begin, $length)');
      if (!remoteEnableFastPeer || !_remoteAllowFastPieces.contains(index)) {
        return false;
      }
    }

    if (!addRequest(index, begin, length)) {
      return false;
    }
    _sendRequestMessage(index, begin, length);
    startRequestDataTimeout();
    return true;
  }

  void _sendRequestMessage(int index, int begin, int length) {
    var bytes = Uint8List(12);
    var view = ByteData.view(bytes.buffer);
    view.setUint32(0, index, Endian.big);
    view.setUint32(4, begin, Endian.big);
    view.setUint32(8, length, Endian.big);
    sendMessage(ID_REQUEST, bytes);
  }

  @override
  List<List<int>> get currentRequestBuffer => _requestBuffer;

  /// Cancel a specific request by removing it from the request queue.
  ///
  /// If the request is present in the queue, it will be removed; otherwise, this operation will simply return.
  void requestCancel(int index, int begin, int length) {
    var request = removeRequest(index, begin, length);
    if (request != null) {
      _sendCancel(index, begin, length);
    }
  }

  @override
  void orderResendRequest(int index, int begin, int length, int resend) {
    _requestBuffer.add([
      index,
      begin,
      length,
      DateTime.now().microsecondsSinceEpoch,
      resend + 1
    ]);
  }

  /// `bitfield: <len=0001+X><id=5><bitfield>`
  ///
  /// The `bitfield` message may only be sent immediately after the handshaking sequence is completed,
  /// and before any other messages are sent. It is optional, and need not be sent if a client has no pieces.
  /// However,if no pieces to send and remote peer enable fast extension, it will send `Have None` message,
  /// and if have all pieces, it will send `Have All` message instead of bitfield buffer.
  ///
  /// The `bitfield` message is variable length, where X is the length of the bitfield. The payload is a
  /// bitfield representing the pieces that have been successfully downloaded. The high bit in the first byte
  /// corresponds to piece index 0. Bits that are cleared indicated a missing piece, and set bits indicate a
  /// valid and available piece. Spare bits at the end are set to zero.
  ///
  void sendBitfield(Bitfield bitfield) {
    _log.fine('Sending bitfile information to the peer: ${bitfield.buffer}');
    if (_bitfieldSended) return;
    _bitfieldSended = true;
    if (remoteEnableFastPeer && localEnableFastPeer) {
      if (bitfield.haveNone()) {
        sendHaveNone();
      } else if (bitfield.haveAll()) {
        sendHaveAll();
      } else {
        sendMessage(ID_BITFIELD, bitfield.buffer);
      }
    } else {
      // According to BEP 0003, bitfield is optional if we have no pieces
      // But we should send it if we have any pieces, or if we want to indicate we have none
      // For compatibility, always send bitfield if we have any pieces
      if (bitfield.haveCompletePiece()) {
        sendMessage(ID_BITFIELD, bitfield.buffer);
      }
      // If we have no pieces, we don't send bitfield (this is allowed by BEP 0003)
      // But peers may not be interested in us if we don't send bitfield
      // So we should still send interested to them if they have pieces we need
    }
  }

  /// `have: <len=0005><id=4><piece index>`
  ///
  /// The `have` message is fixed length. The payload is the zero-based
  /// index of a piece that has just been successfully downloaded and verified via the hash.
  void sendHave(int index) {
    var bytes = Uint8List(4);
    _log.fine('Sending have information to the peer: $bytes, $index');
    ByteData.view(bytes.buffer).setUint32(0, index, Endian.big);
    sendMessage(ID_HAVE, bytes);
  }

  /// - `choke: <len=0001><id=0>`
  /// - `unchoke: <len=0001><id=1>`
  ///
  /// The `choke`/`unchoke` message is fixed-length and has no payload.
  ///
  /// Per BEP 6: When choking, we MUST reject all pending requests except
  /// those for pieces in the allowed fast set. We SHOULD choke first and
  /// then reject requests so that the peer receiving the choke does not
  /// re-request the pieces.
  void sendChoke(bool choke) {
    if (chokeRemote == choke) {
      return;
    }
    chokeRemote = choke;
    var id = ID_CHOKE;
    if (!choke) id = ID_UNCHOKE;
    sendMessage(id);

    // Per BEP 6: When choking, reject all pending requests except allowed fast
    if (choke && remoteEnableFastPeer && localEnableFastPeer) {
      // Reject all pending requests that are not in allowed fast set
      final requestsToReject = <List<int>>[];
      for (var request in _remoteRequestBuffer) {
        final index = request[0];
        final begin = request[1];
        final length = request[2];
        // Don't reject if piece is in allowed fast set
        if (!_allowFastPieces.contains(index)) {
          requestsToReject.add([index, begin, length]);
        }
      }

      // Send reject messages for all non-allowed-fast requests
      for (var request in requestsToReject) {
        sendRejectRequest(request[0], request[1], request[2]);
      }

      if (requestsToReject.isNotEmpty) {
        _log.fine(
            'Rejected ${requestsToReject.length} pending requests after choking peer $address');
      }
    }
  }

  ///Send interested or not interested to the other party to indicate whether you are interested in its resources or not.
  ///
  /// - `interested: <len=0001><id=2>`
  /// - `not interested: <len=0001><id=3>`
  ///
  /// The `interested`/`not interested` message is fixed-length and has no payload.
  void sendInterested(bool iamInterested) {
    if (interestedRemote == iamInterested) {
      return;
    }
    interestedRemote = iamInterested;
    var id = ID_INTERESTED;
    if (!iamInterested) id = ID_NOT_INTERESTED;
    _log.fine(
        'iam interested: $iamInterested, send id: $id to remote peer $address');
    sendMessage(id);
  }

  /// Send hash request message (BEP 52)
  ///
  /// Hash request format: pieces root (32 bytes), base layer (1 byte),
  /// index (4 bytes), length (4 bytes), proof layers (1 byte)
  void sendHashRequest(Uint8List piecesRoot, int baseLayer, int index,
      int length, int proofLayers) {
    if (piecesRoot.length != 32) {
      _log.warning('Invalid pieces root length: ${piecesRoot.length}');
      return;
    }

    var bytes = Uint8List(42);
    var offset = 0;
    bytes.setRange(offset, offset + 32, piecesRoot);
    offset += 32;
    bytes[offset] = baseLayer;
    offset += 1;
    var view = ByteData.view(bytes.buffer, offset);
    view.setUint32(0, index, Endian.big);
    offset += 4;
    view.setUint32(4, length, Endian.big);
    offset += 4;
    bytes[offset] = proofLayers;

    sendMessage(ID_HASH_REQUEST, bytes);
  }

  /// Send hashes message (BEP 52)
  ///
  /// Hashes format: pieces root (32 bytes), base layer (1 byte),
  /// index (4 bytes), length (4 bytes), proof layers (1 byte), hashes (variable)
  void sendHashes(Uint8List piecesRoot, int baseLayer, int index, int length,
      int proofLayers, Uint8List hashes) {
    if (piecesRoot.length != 32) {
      _log.warning('Invalid pieces root length: ${piecesRoot.length}');
      return;
    }

    var bytes = Uint8List(42 + hashes.length);
    var offset = 0;
    bytes.setRange(offset, offset + 32, piecesRoot);
    offset += 32;
    bytes[offset] = baseLayer;
    offset += 1;
    var view = ByteData.view(bytes.buffer, offset);
    view.setUint32(0, index, Endian.big);
    offset += 4;
    view.setUint32(4, length, Endian.big);
    offset += 4;
    bytes[offset] = proofLayers;
    offset += 1;
    bytes.setRange(offset, offset + hashes.length, hashes);

    sendMessage(ID_HASHES, bytes);
  }

  /// Send hash reject message (BEP 52)
  ///
  /// Hash reject has the same format as hash request
  void sendHashReject(Uint8List piecesRoot, int baseLayer, int index,
      int length, int proofLayers) {
    if (piecesRoot.length != 32) {
      _log.warning('Invalid pieces root length: ${piecesRoot.length}');
      return;
    }

    var bytes = Uint8List(42);
    var offset = 0;
    bytes.setRange(offset, offset + 32, piecesRoot);
    offset += 32;
    bytes[offset] = baseLayer;
    offset += 1;
    var view = ByteData.view(bytes.buffer, offset);
    view.setUint32(0, index, Endian.big);
    offset += 4;
    view.setUint32(4, length, Endian.big);
    offset += 4;
    bytes[offset] = proofLayers;

    sendMessage(ID_HASH_REJECT, bytes);
  }

  /// `cancel: <len=0013><id=8><index><begin><length>`
  ///
  /// The `cancel` message is fixed length, and is used to cancel block requests.
  /// The payload is identical to that of the "request" message. It is typically used during "End Game"
  void _sendCancel(int index, int begin, int length) {
    var bytes = Uint8List(12);
    var view = ByteData.view(bytes.buffer);
    view.setUint32(0, index, Endian.big);
    view.setUint32(4, begin, Endian.big);
    view.setUint32(8, length, Endian.big);
    sendMessage(ID_CANCEL, bytes);
  }

  /// `port: <len=0003><id=9><listen-port>`
  ///
  /// The [port] message is sent by newer versions of the Mainline that implements a DHT tracker.
  /// The listen port is the port this peer's DHT node is listening on. This peer should be
  /// inserted in the local routing table (if DHT tracker is supported).
  void sendPortChange(int port) {
    var bytes = Uint8List(2);
    ByteData.view(bytes.buffer).setUint16(0, port);
    sendMessage(ID_PORT, bytes);
  }

  /// [BEP 0006](http://www.bittorrent.org/beps/bep_0006.html)
  ///
  /// Have all message
  void sendHaveAll() {
    if (remoteEnableFastPeer && localEnableFastPeer) {
      sendMessage(OP_HAVE_ALL);
    }
  }

  /// [BEP 0006](http://www.bittorrent.org/beps/bep_0006.html)
  ///
  /// Have none message
  void sendHaveNone() {
    if (remoteEnableFastPeer && localEnableFastPeer) {
      sendMessage(OP_HAVE_NONE);
    }
  }

  /// [BEP 0006](http://www.bittorrent.org/beps/bep_0006.html)
  /// `*Suggest Piece*: <len=0x0005><op=0x0D><index>`
  ///
  /// `Suggest Piece` is an advisory message meaning "you might like to download this piece."
  /// The intended usage is for 'super-seeding' without throughput reduction, to avoid redundant
  /// downloads, and so that a seed which is disk I/O bound can upload contiguous or identical
  /// pieces to avoid excessive disk seeks.
  ///
  /// In all cases, the seed SHOULD operate to maintain a roughly equal number of copies of each
  /// piece in the network. A peer MAY send more than one suggest piece message at any given time.
  /// A peer receiving multiple suggest piece messages MAY interpret this as meaning that all of
  /// the suggested pieces are equally appropriate.
  ///
  void sendSuggestPiece(int index) {
    if (remoteEnableFastPeer && localEnableFastPeer) {
      var bytes = Uint8List(4);
      var view = ByteData.view(bytes.buffer);
      view.setUint32(0, index, Endian.big);
      sendMessage(OP_SUGGEST_PIECE, bytes);
    }
  }

  /// [BEP 0006](http://www.bittorrent.org/beps/bep_0006.html)
  ///
  /// `*Reject Request*: <len=0x000D><op=0x10><index><begin><length>`
  ///
  /// Reject Request notifies a requesting peer that its request will not be satisfied.
  ///
  void sendRejectRequest(int index, int begin, int length) {
    if (remoteEnableFastPeer && localEnableFastPeer) {
      var bytes = Uint8List(12);
      var view = ByteData.view(bytes.buffer);
      view.setUint32(0, index, Endian.big);
      view.setUint32(4, begin, Endian.big);
      view.setUint32(8, length, Endian.big);
      sendMessage(OP_REJECT_REQUEST, bytes);
    }
  }

  /// [BEP 0006](http://www.bittorrent.org/beps/bep_0006.html)
  ///
  /// `*Allowed Fast*: <len=0x0005><op=0x11><index>`
  ///
  /// `Allowed Fast` is an advisory message which means "if you ask for this piece,
  /// I'll give it to you even if you're choked."
  ///
  /// `Allowed Fast` thus shortens the awkward stage during which the peer obtains occasional
  ///  optimistic unchokes but cannot sufficiently reciprocate to remain unchoked.
  ///
  void sendAllowFast(int index) {
    if (remoteEnableFastPeer && localEnableFastPeer) {
      if (_allowFastPieces.add(index)) {
        var bytes = Uint8List(4);
        var view = ByteData.view(bytes.buffer);
        view.setUint32(0, index, Endian.big);
        sendMessage(OP_ALLOW_FAST, bytes);
      }
    }
  }

  /// Generate and send Allowed Fast set according to BEP 6
  ///
  /// The Allowed Fast set is generated deterministically using the canonical algorithm
  /// specified in BEP 6:
  ///
  /// 1. Use only the 3 most significant bytes of IP address (0xFFFFFF00 & ip)
  /// 2. Concatenate with info hash (20 bytes)
  /// 3. Iteratively compute SHA-1 hashes until k unique piece indices are generated
  /// 4. From each 20-byte hash, extract 5 piece indices (each 4 bytes)
  /// 5. Continue until k unique indices are obtained (k=10 by default)
  ///
  /// This ensures that if two peers offer k pieces fast, it will be the same k pieces.
  void _generateAndSendAllowedFastSet() {
    const k = 10; // Default number of allowed fast pieces (per BEP 6)
    try {
      // Extract IP address from peer address
      final ipAddress = address.address;

      // Get IP address bytes (IPv4 only for now)
      Uint8List ipBytes;
      if (ipAddress.type == InternetAddressType.IPv4) {
        ipBytes = Uint8List.fromList(ipAddress.rawAddress);
      } else {
        // IPv6 not supported for Allowed Fast set generation (BEP 6 specifies IPv4)
        _log.warning(
            'Cannot generate Allowed Fast set: IPv6 not supported, peer: $address');
        return;
      }

      if (ipBytes.length != 4) {
        _log.warning(
            'Cannot generate Allowed Fast set: Invalid IP address length: ${ipBytes.length}');
        return;
      }

      // Step 1: Use only 3 most significant bytes (0xFFFFFF00 & ip)
      // Convert IP to 32-bit integer in network byte order
      final ipInt = ByteData.view(ipBytes.buffer).getUint32(0, Endian.big);
      final maskedIp = ipInt & 0xFFFFFF00; // Mask last byte

      // Convert back to bytes (4 bytes, but last byte is 0)
      final maskedIpBytes = Uint8List(4);
      ByteData.view(maskedIpBytes.buffer).setUint32(0, maskedIp, Endian.big);

      // Get info hash (use first 20 bytes for v1 compatibility)
      final infoHash = _infoHashBuffer.length >= 20
          ? Uint8List.fromList(_infoHashBuffer.sublist(0, 20))
          : Uint8List.fromList(_infoHashBuffer);

      // Step 2: Concatenate masked IP with info hash
      var x = Uint8List(maskedIpBytes.length + infoHash.length);
      x.setRange(0, maskedIpBytes.length, maskedIpBytes);
      x.setRange(maskedIpBytes.length, x.length, infoHash);

      // Step 3: Iteratively generate hashes until we have k unique pieces
      final allowedPieces = <int>{};
      while (allowedPieces.length < k) {
        // Compute SHA-1 hash
        final hash = sha1.convert(x);
        final hashBytes = Uint8List.fromList(hash.bytes);

        // Step 4: Extract 5 piece indices from this 20-byte hash
        // Each index is 4 bytes (big-endian)
        for (var i = 0; i < 5 && allowedPieces.length < k; i++) {
          final j = i * 4;
          if (j + 4 > hashBytes.length) break;

          // Extract 4 bytes and convert to 32-bit integer (big-endian)
          final yBytes = hashBytes.sublist(j, j + 4);
          final y = ByteData.view(yBytes.buffer).getUint32(0, Endian.big);

          // Step 5: Compute piece index
          final pieceIndex = y % _piecesNum;

          // Step 6: Add to set if not already present
          if (allowedPieces.add(pieceIndex)) {
            // Send Allow Fast message
            sendAllowFast(pieceIndex);
            _log.fine(
                'Generated Allowed Fast piece $pieceIndex for peer $address');
          }
        }

        // Use the hash as input for next iteration
        x = hashBytes;
      }

      if (allowedPieces.isEmpty) {
        _log.warning('No Allowed Fast pieces generated for peer $address');
      } else {
        _log.fine(
            'Generated ${allowedPieces.length} Allowed Fast pieces for peer $address: $allowedPieces');
      }
    } catch (e, stackTrace) {
      _log.warning('Failed to generate Allowed Fast set for peer $address', e,
          stackTrace);
    }
  }

  /// Countdown started.
  ///
  /// Over `countdownTime` seconds , peer will close to disconnect the remote.
  /// but if peer send or receive any message from/to remote during countdown,
  /// it will re-countdown.
  void _startToCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer(Duration(seconds: countdownTime), () {
      dispose('Over $countdownTime seconds no communication, close');
    });
  }

  /// The Peer has been disposed.
  ///
  /// After disposal, the Peer will no longer be able to send or receive data, its state data will be reset to its initial state, and all previously added event listeners will be removed.
  Future dispose([dynamic reason]) async {
    if (_disposed) return;
    _disposeReason = reason;
    _disposed = true;
    _handShaked = false;
    _bitfieldSended = false;
    events.emit(PeerDisposeEvent(this, reason));
    events.dispose();
    clearExtendedProcessors();
    clearCC();
    stopSpeedCalculator();
    var re = _streamChunk?.cancel();
    _streamChunk = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    return re;
  }

  @override
  String toString() {
    return '$type:${_remotePeerId?.codeUnits != null ? Uint8List.fromList(_remotePeerId!.codeUnits).toHexString() : ''} $address $source';
  }

  @override
  int get hashCode => address.address.address.hashCode;

  @override
  bool operator ==(other) {
    if (other is Peer) {
      return other.address.address.address == address.address.address;
    }
    return false;
  }
}

/// Non-recoverable peer error that indicates reconnect is not required.
class BadException implements Exception {
  /// Underlying error object.
  final dynamic e;

  /// Creates a non-retryable peer exception wrapper.
  BadException(this.e);

  @override
  String toString() {
    return 'No need to reconnect error: $e';
  }
}

class TCPConnectException implements Exception {
  final Exception _e;
  TCPConnectException(this._e);

  @override
  String toString() => _e.toString();
}

class _TCPPeer extends Peer {
  Socket? _socket;
  final ProxyManager? _proxyManager;

  _TCPPeer(CompactAddress address, List<int> infoHashBuffer, int piecesNum,
      this._socket, PeerSource source,
      {bool enableExtend = true,
      bool enableFast = true,
      ProxyManager? proxyManager})
      : _proxyManager = proxyManager,
        super(address, infoHashBuffer, piecesNum, source,
            type: PeerType.TCP,
            localEnableExtended: enableExtend,
            localEnableFastPeer: enableFast);

  @override
  Future<Stream<Uint8List>?> connectRemote(int? timeout) async {
    timeout ??= 30;
    try {
      if (_socket != null) return _socket;

      // Use proxy if configured and enabled for peers
      if (_proxyManager != null && _proxyManager!.shouldUseForPeers()) {
        _socket = await _proxyManager!.connectThroughProxy(
          address.address,
          address.port,
          timeout: Duration(seconds: timeout),
        );
      } else {
        _socket = await Socket.connect(
          address.address,
          address.port,
          timeout: Duration(seconds: timeout),
        );
      }
      return _socket;
    } on Exception catch (e) {
      throw TCPConnectException(e);
    }
  }

  @override
  void sendByteMessage(List<int> bytes) {
    try {
      _socket?.add(bytes);
    } catch (e) {
      dispose(e);
    }
  }

  @override
  Future dispose([reason]) async {
    try {
      await _socket?.close();
      _socket?.destroy();
      _socket = null;
    } catch (e) {
      // do nothing
    } finally {
      super.dispose(reason);
    }
  }
}

///
/// Currently , each uTP Peer use a single UTPSocketClient,
/// actually , one UTPSocketClient should maintain several uTP socket(uTP peer),
/// this class need to improve.
class _UTPPeer extends Peer {
  UTPSocketClient? _client;
  UTPSocket? _socket;
  _UTPPeer(
    CompactAddress address,
    List<int> infoHashBuffer,
    int piecesNum,
    this._socket,
    PeerSource source, {
    bool enableExtend = true,
    bool enableFast = true,
  }) : super(address, infoHashBuffer, piecesNum, source,
            type: PeerType.UTP,
            localEnableExtended: enableExtend,
            localEnableFastPeer: enableFast) {
    // Initialize uTP with optimized congestion window for better performance
    initializeUtpCwnd();
  }

  @override
  Future<Stream<Uint8List>?> connectRemote(int timeout) async {
    try {
      if (_socket != null) return _socket;
      _client ??= UTPSocketClient();
      _socket = await _client?.connect(address.address, address.port);
      // Note: Errors from socket stream are handled in Peer.connect() via onError callback
      return _socket;
    } on RangeError catch (e, stackTrace) {
      var reason = 'CONNECT_REMOTE';
      Peer._recordRangeError(reason, isUtp: true);
      _log.severe(
          'RangeError in _UTPPeer.connectRemote: peer=$address, error=${e.message}',
          e,
          stackTrace);
      dispose('UTP_CONNECT_RANGE_ERROR');
      return null;
    } catch (e, stackTrace) {
      _log.warning(
          'Error in _UTPPeer.connectRemote: peer=$address', e, stackTrace);
      dispose('UTP_CONNECT_ERROR');
      return null;
    }
  }

  @override
  void sendByteMessage(List<int> bytes) {
    try {
      if (bytes.isEmpty) {
        _log.warning('Attempting to send empty message to peer $address');
        return;
      }

      // Validate bytes list bounds
      if (bytes.length > MAX_MESSAGE_SIZE) {
        _log.warning('Message too large: ${bytes.length} bytes, peer=$address');
        return;
      }

      try {
        _socket?.add(Uint8List.fromList(bytes));

        // Log successful send for uTP debugging (only in fine mode to avoid spam)
        if (type == PeerType.UTP) {
          _log.fine(
              'uTP sent message: peer=$address, bytesLength=${bytes.length}');
        }
      } on RangeError catch (e, stackTrace) {
        // Catch RangeError from Uint8List.fromList if bytes has invalid range
        var reason = 'UINT8LIST_CONVERSION';
        Peer._recordRangeError(reason, isUtp: true);
        _log.severe(
            'RangeError converting bytes to Uint8List: peer=$address, bytesLength=${bytes.length}, error=${e.message}',
            e,
            stackTrace);
        dispose('UTP_CONVERSION_RANGE_ERROR');
        return;
      }
    } on RangeError catch (e, stackTrace) {
      var reason = 'SEND_BYTE_MESSAGE';
      Peer._recordRangeError(reason, isUtp: true);
      _log.severe(
          'RangeError in _UTPPeer.sendByteMessage: peer=$address, bytesLength=${bytes.length}, error=${e.message}',
          e,
          stackTrace);
      dispose('UTP_SEND_RANGE_ERROR');
    } catch (e, stackTrace) {
      _log.severe(
          'Error in _UTPPeer.sendByteMessage: peer=$address', e, stackTrace);
      dispose('UTP_SEND_ERROR');
    }
  }

  @override
  Future dispose([reason]) async {
    await _socket?.close();
    await _client?.close();
    return super.dispose(reason);
  }
}
