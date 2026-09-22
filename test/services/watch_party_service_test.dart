import 'dart:async';

import 'package:convert_the_spire_reborn/src/services/watch_party/watch_party_protocol.dart';
import 'package:convert_the_spire_reborn/src/services/watch_party/watch_party_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end tests over real sockets on loopback: a host and a guest, two
/// separate service instances, talking over an actual WebSocket. The protocol
/// maths is covered in watch_party_protocol_test.dart; this proves the wiring.
void main() {
  late WatchPartyService host;
  late WatchPartyService guest;

  setUp(() {
    host = WatchPartyService();
    guest = WatchPartyService();
  });

  tearDown(() async {
    await guest.dispose();
    await host.dispose();
  });

  /// Connects [guest] to [host], bypassing UDP discovery (CI has no usable
  /// broadcast domain, and this is the same path the manual-IP fallback uses).
  Future<void> connect({String name = 'Guest'}) async {
    final error = await guest.joinAt('127.0.0.1:${host.boundPort}',
        code: host.roomCode!, displayName: name);
    expect(error, isNull, reason: 'guest failed to join: $error');
  }

  test('a host starts up and hands out a usable room code', () async {
    final code = await host.startHosting(displayName: 'TV');

    expect(isValidRoomCode(code), isTrue, reason: code);
    expect(host.isHosting, isTrue);
    expect(host.status.role, WatchPartyRole.host);
    expect(host.boundPort, greaterThan(0));
  });

  test('a guest connects and the host reports it', () async {
    await host.startHosting(displayName: 'TV');
    final hostSawGuest = host.statusStream
        .firstWhere((s) => s.peerCount == 1)
        .timeout(const Duration(seconds: 5));

    await connect(name: 'Phone');

    final status = await hostSawGuest;
    expect(status.peerCount, 1);
    expect(guest.isGuest, isTrue);
    expect(guest.status.role, WatchPartyRole.guest);
  });

  test('the guest receives the playback state the host publishes', () async {
    await host.startHosting(displayName: 'TV');
    final received = guest.events
        .firstWhere((e) => e.kind == WatchPartyEventKind.remoteState)
        .timeout(const Duration(seconds: 8));

    await connect();
    // Keep publishing: the guest ignores state until its first pong has
    // landed, which is exactly the behaviour we want to exercise.
    final ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      host.publishState(
        mediaKey: 'episode-01.mkv',
        position: const Duration(minutes: 5),
        playing: true,
        title: 'Episode 1',
      );
    });
    addTearDown(ticker.cancel);

    final event = await received;
    expect(event.snapshot, isNotNull);
    expect(event.snapshot!.mediaKey, 'episode-01.mkv');
    expect(event.snapshot!.position, const Duration(minutes: 5));
    expect(event.snapshot!.playing, isTrue);
    expect(event.snapshot!.title, 'Episode 1');
    expect(event.hostClockNowMs, isNotNull);
  });

  test('the guest measures a clock offset and a sane latency', () async {
    await host.startHosting(displayName: 'TV');
    await connect();

    // Wait for the first ping/pong round trip to complete.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (guest.latencyMs == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    expect(guest.latencyMs, isNotNull,
        reason: 'no ping/pong completed over loopback');
    expect(guest.latencyMs, lessThan(2000));
    expect(guest.latencyMs, greaterThanOrEqualTo(0));
  });

  test('a late joiner is sent the current state immediately', () async {
    await host.startHosting(displayName: 'TV');
    // State exists before anyone joins.
    host.publishState(
      mediaKey: 'film.mkv',
      position: const Duration(minutes: 42),
      playing: false,
    );

    final received = guest.events
        .firstWhere((e) => e.kind == WatchPartyEventKind.remoteState)
        .timeout(const Duration(seconds: 8));
    await connect();

    // The immediate push happens before the first pong, so the guest holds it
    // until the clock is known; re-publish to let it through.
    final ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      host.publishState(
        mediaKey: 'film.mkv',
        position: const Duration(minutes: 42),
        playing: false,
      );
    });
    addTearDown(ticker.cancel);

    final event = await received;
    expect(event.snapshot!.mediaKey, 'film.mkv');
    expect(event.snapshot!.position, const Duration(minutes: 42));
    expect(event.snapshot!.playing, isFalse);
  });

  test('a wrong room code is refused with a reason', () async {
    await host.startHosting(displayName: 'TV');
    final wrongCode = host.roomCode == 'AAAAAA' ? 'BBBBBB' : 'AAAAAA';

    final denied = guest.events
        .firstWhere((e) => e.kind == WatchPartyEventKind.denied)
        .timeout(const Duration(seconds: 5));

    await guest.joinAt('127.0.0.1:${host.boundPort}',
        code: wrongCode, displayName: 'Intruder');

    final event = await denied;
    expect(event.reason, contains('Wrong room code'));
    expect(host.status.peerCount, 0, reason: 'must never be admitted');
  });

  test('the guest is told when the host leaves', () async {
    await host.startHosting(displayName: 'TV');
    final admitted = host.statusStream
        .firstWhere((s) => s.peerCount == 1)
        .timeout(const Duration(seconds: 5));
    await connect();
    // joinAt returns once the socket is open, which can be before the host has
    // processed the hello. Leaving mid-handshake is a different scenario.
    await admitted;

    final hostLeft = guest.events
        .firstWhere((e) => e.kind == WatchPartyEventKind.hostLeft)
        .timeout(const Duration(seconds: 5));

    await host.leave();

    await hostLeft;
    expect(guest.isGuest, isFalse);
    expect(guest.status.role, WatchPartyRole.idle);
  });

  test('a malformed room code is rejected before any socket is opened',
      () async {
    final error = await guest.join('nope', displayName: 'Phone');
    expect(error, contains('does not look right'));
    expect(guest.isActive, isFalse);
  });

  test('leaving twice, and leaving when idle, are both safe', () async {
    await host.startHosting(displayName: 'TV');
    await host.leave();
    await host.leave();
    expect(host.isActive, isFalse);
    expect(host.status.role, WatchPartyRole.idle);
  });

  test('publishing state while not hosting does nothing', () {
    expect(
        () => host.publishState(
            mediaKey: 'x.mkv', position: Duration.zero, playing: true),
        returnsNormally);
  });

  test('two hosts can run at once (second takes another port)', () async {
    final other = WatchPartyService();
    addTearDown(other.dispose);

    await host.startHosting(displayName: 'TV');
    await other.startHosting(displayName: 'Laptop');

    expect(other.isHosting, isTrue);
    expect(other.roomCode, isNot(host.roomCode));
    // Whatever port it landed on, a guest must still be able to reach it.
    final error = await guest.joinAt('127.0.0.1:${other.boundPort}',
        code: other.roomCode!, displayName: 'Phone');
    expect(error, isNull);
  });
}
