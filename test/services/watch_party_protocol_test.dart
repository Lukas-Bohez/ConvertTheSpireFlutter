import 'dart:math';

import 'package:convert_the_spire_reborn/src/services/watch_party/watch_party_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

/// Watch Together lives or dies on these rules, so they are tested directly
/// rather than through sockets. Every case here is one that actually happens
/// in a living room: a phone joining late, a guest that paused on its own, a
/// laggy wifi link, someone typing the room code with spaces in it.
void main() {
  group('room codes', () {
    test('generated codes are the right shape and always valid', () {
      final rng = Random(1234);
      for (var i = 0; i < 200; i++) {
        final code = generateRoomCode(rng);
        expect(code.length, kRoomCodeLength);
        expect(isValidRoomCode(code), isTrue, reason: code);
      }
    });

    test('codes never contain the characters people misread', () {
      final rng = Random(99);
      for (var i = 0; i < 200; i++) {
        expect(generateRoomCode(rng), isNot(matches(RegExp(r'[0O1IL]'))));
      }
    });

    test('typed input is cleaned up: spaces, dashes, lower case', () {
      expect(normaliseRoomCode('  ab2-3d4 '), 'AB23D4');
      expect(normaliseRoomCode('a b 2 3 d 4'), 'AB23D4');
    });

    test('lookalike characters are dropped, never silently substituted', () {
      // Turning a typo into a *different valid code* would send someone to the
      // wrong room with a confusing error. A short code fails cleanly instead.
      final result = normaliseRoomCode('AB0IL4');
      expect(result, 'AB4');
      expect(isValidRoomCode(result), isFalse);
    });

    test('a correct code round-trips through normalisation untouched', () {
      final code = generateRoomCode(Random(7));
      expect(normaliseRoomCode(code.toLowerCase()), code);
    });
  });

  group('clock offset estimation', () {
    test('a symmetric round trip recovers the offset exactly', () {
      // Host clock runs 5000ms ahead. Guest sends at 1000, host replies at
      // 6100 (its own clock), guest receives at 1200 => rtt 200, offset 5000.
      final estimator = ClockOffsetEstimator();
      estimator.addSample(sentAtMs: 1000, hostClockMs: 6100, receivedAtMs: 1200);

      expect(estimator.hasEstimate, isTrue);
      expect(estimator.offsetMs, 5000);
      expect(estimator.hostClockNow(2000), 7000);
    });

    test('the lowest-latency sample wins, so one slow packet cannot skew it',
        () {
      final estimator = ClockOffsetEstimator();
      // Clean sample: rtt 20ms, true offset 5000.
      estimator.addSample(sentAtMs: 1000, hostClockMs: 6010, receivedAtMs: 1020);
      // Badly delayed reply: rtt 900ms, would imply a wildly wrong offset.
      estimator.addSample(sentAtMs: 2000, hostClockMs: 7050, receivedAtMs: 2900);

      expect(estimator.bestRttMs, 20);
      expect(estimator.offsetMs, 5000);
    });

    test('a negative round trip is discarded rather than trusted', () {
      final estimator = ClockOffsetEstimator();
      estimator.addSample(sentAtMs: 5000, hostClockMs: 1, receivedAtMs: 4000);
      expect(estimator.hasEstimate, isFalse);
      // With no estimate it reports a zero offset rather than a wrong one.
      expect(estimator.offsetMs, 0);
    });

    test('only the most recent samples are kept', () {
      final estimator = ClockOffsetEstimator(maxSamples: 3);
      for (var i = 0; i < 10; i++) {
        estimator.addSample(
            sentAtMs: i * 100, hostClockMs: i * 100 + 50, receivedAtMs: i * 100 + 40);
      }
      // Still produces an estimate, and has not grown without bound.
      expect(estimator.hasEstimate, isTrue);
      expect(estimator.bestRttMs, 40);
    });
  });

  group('sync decisions', () {
    const media = 'episode-01.mkv';

    PlaybackSnapshot snap({
      Duration position = const Duration(seconds: 30),
      bool playing = true,
      int clock = 10000,
      String key = media,
    }) =>
        PlaybackSnapshot(
            mediaKey: key,
            position: position,
            playing: playing,
            hostClockMs: clock);

    test('a guest already in step is left alone', () {
      final decision = computeSyncDecision(
        snapshot: snap(),
        localMediaKey: media,
        localPosition: const Duration(seconds: 30),
        localPlaying: true,
        hostClockNowMs: 10000,
      );
      expect(decision.action, SyncAction.none);
    });

    test('the host position is projected forward by the message age', () {
      // Snapshot says 30s at host clock 10000. It is now host clock 12000, so
      // the host is really at 32s. A guest sitting at 30s is 2s behind.
      final decision = computeSyncDecision(
        snapshot: snap(),
        localMediaKey: media,
        localPosition: const Duration(seconds: 30),
        localPlaying: true,
        hostClockNowMs: 12000,
      );
      expect(decision.action, SyncAction.seek);
      expect(decision.targetPosition, const Duration(seconds: 32));
      expect(decision.driftMs, 2000);
    });

    test('a paused host is NOT projected forward', () {
      // This is the bug that makes everyone drift while the host is paused.
      final decision = computeSyncDecision(
        snapshot: snap(playing: false),
        localMediaKey: media,
        localPosition: const Duration(seconds: 30),
        localPlaying: false,
        hostClockNowMs: 999999,
      );
      expect(decision.action, SyncAction.none);
    });

    test('small drift is tolerated instead of seeking constantly', () {
      // Half a second out: correcting this is more jarring than living with it.
      final decision = computeSyncDecision(
        snapshot: snap(),
        localMediaKey: media,
        localPosition: const Duration(milliseconds: 29500),
        localPlaying: true,
        hostClockNowMs: 10000,
      );
      expect(decision.action, SyncAction.none);
      expect(decision.driftMs, 500);
    });

    test('drift just past the tolerance does trigger a seek', () {
      final decision = computeSyncDecision(
        snapshot: snap(),
        localMediaKey: media,
        localPosition: const Duration(milliseconds: 29200),
        localPlaying: true,
        hostClockNowMs: 10000,
      );
      expect(decision.action, SyncAction.seek);
      expect(decision.driftMs, 800);
    });

    test('a guest running ahead is pulled back', () {
      final decision = computeSyncDecision(
        snapshot: snap(),
        localMediaKey: media,
        localPosition: const Duration(seconds: 45),
        localPlaying: true,
        hostClockNowMs: 10000,
      );
      expect(decision.action, SyncAction.seek);
      expect(decision.driftMs, -15000);
      expect(decision.targetPosition, const Duration(seconds: 30));
    });

    test('host pauses: the guest pauses too', () {
      final decision = computeSyncDecision(
        snapshot: snap(playing: false),
        localMediaKey: media,
        localPosition: const Duration(seconds: 30),
        localPlaying: true,
        hostClockNowMs: 10000,
      );
      expect(decision.action, SyncAction.pause);
    });

    test('host resumes: the guest resumes, and catches up in the same step',
        () {
      // A guest that was paused while the host played on must not resume at
      // the stale position.
      final decision = computeSyncDecision(
        snapshot: snap(position: const Duration(seconds: 90)),
        localMediaKey: media,
        localPosition: const Duration(seconds: 30),
        localPlaying: false,
        hostClockNowMs: 10000,
      );
      expect(decision.action, SyncAction.play);
      expect(decision.targetPosition, const Duration(seconds: 90));
    });

    test('resuming with only a tiny gap does not add a needless seek', () {
      final decision = computeSyncDecision(
        snapshot: snap(),
        localMediaKey: media,
        localPosition: const Duration(milliseconds: 29900),
        localPlaying: false,
        hostClockNowMs: 10000,
      );
      expect(decision.action, SyncAction.play);
      expect(decision.targetPosition, isNull);
    });

    test('a different file asks the guest to load it', () {
      final decision = computeSyncDecision(
        snapshot: snap(key: 'something-else.mp4'),
        localMediaKey: media,
        localPosition: Duration.zero,
        localPlaying: false,
        hostClockNowMs: 10000,
      );
      expect(decision.action, SyncAction.loadDifferentMedia);
      expect(decision.targetPosition, const Duration(seconds: 30));
    });

    test('a snapshot from the future never rewinds playback', () {
      // Clock estimate can be slightly off; elapsed time is floored at zero so
      // a stale-looking clock cannot produce a negative projection.
      final decision = computeSyncDecision(
        snapshot: snap(clock: 20000),
        localMediaKey: media,
        localPosition: const Duration(seconds: 30),
        localPlaying: true,
        hostClockNowMs: 10000,
      );
      expect(decision.action, SyncAction.none);
    });
  });

  group('messages', () {
    test('a snapshot survives a round trip through the wire format', () {
      const original = PlaybackSnapshot(
        mediaKey: 'film.mkv',
        position: Duration(minutes: 12, seconds: 34),
        playing: true,
        hostClockMs: 987654,
        title: 'A Film',
      );

      final encoded = WatchPartyMessage.stateMessage(original).encode();
      final decoded = WatchPartyMessage.decode(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.type, WatchPartyMessage.state);
      final snapshot = PlaybackSnapshot.fromJson(decoded.data);
      expect(snapshot, isNotNull);
      expect(snapshot!.mediaKey, original.mediaKey);
      expect(snapshot.position, original.position);
      expect(snapshot.playing, original.playing);
      expect(snapshot.hostClockMs, original.hostClockMs);
      expect(snapshot.title, 'A Film');
    });

    test('rubbish on the socket is ignored, never fatal', () {
      for (final junk in ['', 'not json', '[]', '{}', '{"t":123}', 'null']) {
        expect(WatchPartyMessage.decode(junk), isNull, reason: junk);
      }
    });

    test('a snapshot with missing or wrong-typed fields is rejected', () {
      expect(PlaybackSnapshot.fromJson({'media': 'a.mkv'}), isNull);
      expect(
          PlaybackSnapshot.fromJson(
              {'media': 'a.mkv', 'pos': 'soon', 'playing': true, 'clock': 1}),
          isNull);
      expect(
          PlaybackSnapshot.fromJson(
              {'media': 5, 'pos': 1, 'playing': true, 'clock': 1}),
          isNull);
    });
  });

  group('admitting a peer', () {
    test('a matching hello is admitted', () {
      final hello =
          WatchPartyMessage.helloMessage(room: 'AB23D4', name: 'Phone');
      expect(rejectionReasonForHello(message: hello, expectedRoom: 'AB23D4'),
          isNull);
    });

    test('the room code is compared case-insensitively', () {
      final hello =
          WatchPartyMessage.helloMessage(room: 'ab23d4', name: 'Phone');
      expect(rejectionReasonForHello(message: hello, expectedRoom: 'AB23D4'),
          isNull);
    });

    test('a wrong room code is refused', () {
      final hello =
          WatchPartyMessage.helloMessage(room: 'ZZZZZZ', name: 'Phone');
      expect(rejectionReasonForHello(message: hello, expectedRoom: 'AB23D4'),
          contains('Wrong room code'));
    });

    test('a mismatched protocol version is refused with a useful reason', () {
      const hello = WatchPartyMessage(
          WatchPartyMessage.hello, {'room': 'AB23D4', 'name': 'x', 'v': 99});
      final reason =
          rejectionReasonForHello(message: hello, expectedRoom: 'AB23D4');
      expect(reason, contains('different version'));
    });

    test('a first frame that is not a hello is refused', () {
      expect(
          rejectionReasonForHello(
              message: WatchPartyMessage.byeMessage(), expectedRoom: 'AB23D4'),
          isNotNull);
    });
  });
}
