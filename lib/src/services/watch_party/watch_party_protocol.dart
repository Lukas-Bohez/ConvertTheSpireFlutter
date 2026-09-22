/// Wire protocol and clock maths for Watch Together.
///
/// Deliberately free of sockets, timers and Flutter so every rule here can be
/// tested directly. [WatchPartyService] owns the I/O and calls into this.
///
/// How the sync works
/// ------------------
/// The host is the clock. It broadcasts a [PlaybackSnapshot] — what is playing,
/// where, and the host clock reading at that instant. A guest cannot compare
/// that timestamp to its own clock directly (two devices never agree), so it
/// first estimates the offset between the two clocks with [ClockOffsetEstimator]
/// using the same round-trip trick NTP uses. With the offset known it can
/// project where playback *should* be right now and decide what to do, via
/// [computeSyncDecision].
library;

import 'dart:convert';
import 'dart:math';

/// Wire-format version. Bumped when a message shape changes incompatibly; a
/// peer announcing a different version is refused rather than half-understood.
const int kWatchPartyProtocolVersion = 1;

/// Characters used in room codes: no 0/O or 1/I/L, which people mistype when
/// reading a code aloud or off a TV screen.
const String kRoomCodeAlphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
const int kRoomCodeLength = 6;

/// Generates a room code. [random] is injectable so tests are deterministic.
String generateRoomCode([Random? random]) {
  final rng = random ?? Random.secure();
  return List.generate(kRoomCodeLength,
      (_) => kRoomCodeAlphabet[rng.nextInt(kRoomCodeAlphabet.length)]).join();
}

/// Normalises typed input: uppercases and drops anything that cannot appear
/// in a code (spaces, dashes, and the excluded lookalikes 0/O/1/I/L).
///
/// Deliberately does *not* guess substitutions. Mapping a typed `0` onto some
/// other letter would silently turn a typo into a different valid-looking
/// code, and the user would get "wrong room" with no idea why. Dropping it
/// makes the code the wrong length, which is a clear, honest failure.
String normaliseRoomCode(String input) {
  final buffer = StringBuffer();
  for (final rune in input.toUpperCase().runes) {
    final ch = String.fromCharCode(rune);
    if (kRoomCodeAlphabet.contains(ch)) buffer.write(ch);
  }
  return buffer.toString();
}

bool isValidRoomCode(String code) =>
    code.length == kRoomCodeLength &&
    code.runes.every((r) => kRoomCodeAlphabet.contains(String.fromCharCode(r)));

/// What the host is playing, sampled at [hostClockMs].
class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.mediaKey,
    required this.position,
    required this.playing,
    required this.hostClockMs,
    this.title,
  });

  /// Identifies the media across devices. Uses the file name rather than a
  /// full path, because the same episode sits at a different path on each
  /// person's machine.
  final String mediaKey;
  final Duration position;
  final bool playing;

  /// The host's monotonic clock when this was sampled.
  final int hostClockMs;
  final String? title;

  Map<String, dynamic> toJson() => {
        'media': mediaKey,
        'pos': position.inMilliseconds,
        'playing': playing,
        'clock': hostClockMs,
        if (title != null) 'title': title,
      };

  static PlaybackSnapshot? fromJson(Map<String, dynamic> json) {
    final media = json['media'];
    final pos = json['pos'];
    final playing = json['playing'];
    final clock = json['clock'];
    if (media is! String || pos is! num || playing is! bool || clock is! num) {
      return null;
    }
    return PlaybackSnapshot(
      mediaKey: media,
      position: Duration(milliseconds: pos.round()),
      playing: playing,
      hostClockMs: clock.round(),
      title: json['title'] is String ? json['title'] as String : null,
    );
  }

  @override
  String toString() => 'PlaybackSnapshot($mediaKey, ${position.inMilliseconds}ms, '
      'playing=$playing, clock=$hostClockMs)';
}

/// Estimates the offset between this device's clock and the host's.
///
/// One sample is a round trip: the guest sends its clock reading, the host
/// echoes it back alongside its own, and the guest notes the arrival time.
/// Assuming the delay is roughly symmetric,
///
///   offset = hostClock - (sentAt + rtt / 2)
///
/// A single sample can be badly skewed by one slow packet, so samples are kept
/// and the one with the *lowest* round-trip time wins — a fast round trip has
/// the least room for asymmetry. This is what NTP does, and it beats averaging,
/// which lets one delayed packet drag the estimate.
class ClockOffsetEstimator {
  ClockOffsetEstimator({this.maxSamples = 8});

  final int maxSamples;
  final List<({int rttMs, int offsetMs})> _samples = [];

  /// Feeds one completed round trip. All three readings are in milliseconds;
  /// [sentAtMs] and [receivedAtMs] are local, [hostClockMs] is remote.
  void addSample({
    required int sentAtMs,
    required int hostClockMs,
    required int receivedAtMs,
  }) {
    final rtt = receivedAtMs - sentAtMs;
    if (rtt < 0) return; // clock went backwards; unusable
    final offset = hostClockMs - (sentAtMs + rtt ~/ 2);
    _samples.add((rttMs: rtt, offsetMs: offset));
    if (_samples.length > maxSamples) _samples.removeAt(0);
  }

  bool get hasEstimate => _samples.isNotEmpty;

  /// Round-trip time of the sample the estimate is based on.
  int? get bestRttMs => _best?.rttMs;

  ({int rttMs, int offsetMs})? get _best {
    if (_samples.isEmpty) return null;
    var best = _samples.first;
    for (final sample in _samples) {
      if (sample.rttMs < best.rttMs) best = sample;
    }
    return best;
  }

  /// Milliseconds to add to a local clock reading to get the host's.
  int get offsetMs => _best?.offsetMs ?? 0;

  /// The host's clock as it reads right now, given the local clock.
  int hostClockNow(int localClockMs) => localClockMs + offsetMs;

  void reset() => _samples.clear();
}

enum SyncAction {
  /// Close enough; leave playback alone.
  none,

  /// Jump to [SyncDecision.targetPosition].
  seek,

  /// Start playing (optionally after seeking).
  play,

  /// Stop playing (optionally after seeking).
  pause,

  /// The host is on different media entirely.
  loadDifferentMedia,
}

class SyncDecision {
  const SyncDecision(this.action, {this.targetPosition, this.driftMs = 0});

  final SyncAction action;
  final Duration? targetPosition;

  /// How far behind (positive) or ahead (negative) the local player was.
  final int driftMs;

  @override
  String toString() =>
      'SyncDecision($action, target=$targetPosition, drift=${driftMs}ms)';
}

/// Below this the correction is more disruptive than the error, so nothing is
/// done. A hard seek is audible and visible; tolerating a fraction of a second
/// is the better trade.
const int kSyncToleranceMs = 750;

/// Decides what a guest should do to match [snapshot].
///
/// [hostClockNowMs] is the host's clock as it reads *now*, from
/// [ClockOffsetEstimator.hostClockNow] — not the raw local clock.
SyncDecision computeSyncDecision({
  required PlaybackSnapshot snapshot,
  required String localMediaKey,
  required Duration localPosition,
  required bool localPlaying,
  required int hostClockNowMs,
  int toleranceMs = kSyncToleranceMs,
}) {
  if (snapshot.mediaKey != localMediaKey) {
    return SyncDecision(SyncAction.loadDifferentMedia,
        targetPosition: snapshot.position);
  }

  // Project the host's position forward by however long ago the snapshot was
  // taken. A paused host is not moving, so its position is already current.
  final elapsedMs =
      snapshot.playing ? max(0, hostClockNowMs - snapshot.hostClockMs) : 0;
  final expected = snapshot.position + Duration(milliseconds: elapsedMs);
  final driftMs = expected.inMilliseconds - localPosition.inMilliseconds;

  // A play/pause mismatch is always worth acting on, and carries the position
  // with it so a guest that fell behind does not resume at the wrong spot.
  if (localPlaying != snapshot.playing) {
    return SyncDecision(
      snapshot.playing ? SyncAction.play : SyncAction.pause,
      targetPosition: driftMs.abs() > toleranceMs ? expected : null,
      driftMs: driftMs,
    );
  }

  if (driftMs.abs() > toleranceMs) {
    return SyncDecision(SyncAction.seek,
        targetPosition: expected, driftMs: driftMs);
  }

  return SyncDecision(SyncAction.none, driftMs: driftMs);
}

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

/// Envelope kinds. Anything unrecognised is ignored rather than fatal, so an
/// older peer meeting a newer one degrades instead of crashing.
class WatchPartyMessage {
  const WatchPartyMessage(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;

  static const String hello = 'hello';
  static const String welcome = 'welcome';
  static const String ping = 'ping';
  static const String pong = 'pong';
  static const String state = 'state';
  static const String bye = 'bye';
  static const String denied = 'denied';

  String encode() => jsonEncode({'t': type, ...data});

  /// Parses a frame. Returns null for anything malformed — a peer must never
  /// be able to crash the app by sending rubbish down the socket.
  static WatchPartyMessage? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final type = map.remove('t');
      if (type is! String || type.isEmpty) return null;
      return WatchPartyMessage(type, map);
    } catch (_) {
      return null;
    }
  }

  static WatchPartyMessage helloMessage(
          {required String room, required String name}) =>
      WatchPartyMessage(hello,
          {'room': room, 'name': name, 'v': kWatchPartyProtocolVersion});

  static WatchPartyMessage welcomeMessage({required String hostName}) =>
      WatchPartyMessage(
          welcome, {'host': hostName, 'v': kWatchPartyProtocolVersion});

  static WatchPartyMessage deniedMessage(String reason) =>
      WatchPartyMessage(denied, {'reason': reason});

  static WatchPartyMessage pingMessage(int clientClockMs) =>
      WatchPartyMessage(ping, {'c': clientClockMs});

  static WatchPartyMessage pongMessage(
          {required int clientClockMs, required int hostClockMs}) =>
      WatchPartyMessage(pong, {'c': clientClockMs, 'h': hostClockMs});

  static WatchPartyMessage stateMessage(PlaybackSnapshot snapshot) =>
      WatchPartyMessage(state, snapshot.toJson());

  static WatchPartyMessage byeMessage() => const WatchPartyMessage(bye, {});
}

/// Whether a joining peer may be admitted.
///
/// Returns null when everything checks out, or a human-readable reason to send
/// back in a [WatchPartyMessage.denied].
String? rejectionReasonForHello({
  required WatchPartyMessage message,
  required String expectedRoom,
}) {
  if (message.type != WatchPartyMessage.hello) return 'expected a hello';
  final version = message.data['v'];
  if (version is! num || version.round() != kWatchPartyProtocolVersion) {
    return 'This device is running a different version of Watch Together. '
        'Update both apps to the same version.';
  }
  final room = message.data['room'];
  if (room is! String || room.toUpperCase() != expectedRoom.toUpperCase()) {
    return 'Wrong room code.';
  }
  return null;
}
