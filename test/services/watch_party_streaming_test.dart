import 'dart:io';

import 'package:convert_the_spire_reborn/src/services/watch_party/watch_party_protocol.dart';
import 'package:convert_the_spire_reborn/src/services/watch_party/watch_party_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the host media stream.
///
/// Watch Together synced by file name, so everyone in the room had to already
/// own the file - which ruled out watching on a TV or with a friend (issue
/// #7). The host now serves the file it is playing over the room's own server.
void main() {
  late WatchPartyService host;
  late Directory temp;
  late File media;

  setUp(() async {
    host = WatchPartyService();
    temp = await Directory.systemTemp.createTemp('watch_party_stream');
    media = File('${temp.path}${Platform.pathSeparator}episode.mp4');
    await media.writeAsBytes(List<int>.generate(2048, (i) => i % 256));
  });

  tearDown(() async {
    await host.dispose();
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  Uri streamUri(String path) =>
      Uri.parse('http://127.0.0.1:${host.boundPort}$path');

  test('nothing is shared until the host is hosting', () {
    expect(host.shareMedia(media.path), isNull);
  });

  test('a shared file gets a token that keeps its extension', () async {
    await host.startHosting(displayName: 'Host');

    final path = host.shareMedia(media.path)!;

    expect(path, startsWith('/media/'));
    expect(path, endsWith('.mp4'),
        reason: 'the guest decides audio vs video from the extension');
  });

  test('sharing the same file twice keeps the same token', () async {
    await host.startHosting(displayName: 'Host');

    expect(host.shareMedia(media.path), host.shareMedia(media.path),
        reason: 're-publishing must not break a guest mid-stream');
  });

  test('the shared file is served in full', () async {
    await host.startHosting(displayName: 'Host');
    final path = host.shareMedia(media.path)!;

    final client = HttpClient();
    final response = await (await client.getUrl(streamUri(path))).close();
    final bytes = await response
        .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
    client.close();

    expect(response.statusCode, HttpStatus.ok);
    expect(bytes.length, 2048);
    expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
  });

  test('a range request returns just that slice, so guests can seek', () async {
    await host.startHosting(displayName: 'Host');
    final path = host.shareMedia(media.path)!;

    final client = HttpClient();
    final request = await client.getUrl(streamUri(path));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=100-199');
    final response = await request.close();
    final bytes = await response
        .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
    client.close();

    expect(response.statusCode, HttpStatus.partialContent);
    expect(bytes.length, 100);
    expect(bytes.first, 100 % 256);
    expect(response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 100-199/2048');
  });

  test('an unknown token is not served', () async {
    await host.startHosting(displayName: 'Host');

    final client = HttpClient();
    final response =
        await (await client.getUrl(streamUri('/media/deadbeef.mp4'))).close();
    await response.drain<void>();
    client.close();

    expect(response.statusCode, HttpStatus.notFound,
        reason: 'hosting a room must not turn the device into a file server');
  });

  test('leaving the room revokes the shared tokens', () async {
    await host.startHosting(displayName: 'Host');
    final path = host.shareMedia(media.path)!;
    await host.leave();

    // Host again; the old token must not resolve on the new room's server.
    // (Not asserting the same port: when test files run in parallel another
    // suite can hold the default one, and both fall back to random ports.)
    await host.startHosting(displayName: 'Host');

    final client = HttpClient();
    final response = await (await client
            .getUrl(Uri.parse('http://127.0.0.1:${host.boundPort}$path')))
        .close();
    await response.drain<void>();
    client.close();

    expect(response.statusCode, HttpStatus.notFound);
  });

  group('MediaSource', () {
    test('builds an absolute URL from the endpoint the guest joined', () {
      const source = MediaSource(path: '/media/abc.mp4');

      expect(source.urlFor('192.168.1.5:47825'),
          'http://192.168.1.5:47825/media/abc.mp4');
    });

    test('survives a JSON round trip inside a snapshot', () {
      final snapshot = PlaybackSnapshot(
        mediaKey: 'episode.mp4',
        position: const Duration(seconds: 12),
        playing: true,
        hostClockMs: 500,
        source: const MediaSource(path: '/media/abc.mp4'),
      );

      final restored = PlaybackSnapshot.fromJson(snapshot.toJson())!;

      expect(restored.source?.path, '/media/abc.mp4');
    });

    test('an older host that sends no source still parses', () {
      final snapshot = PlaybackSnapshot(
        mediaKey: 'episode.mp4',
        position: Duration.zero,
        playing: false,
        hostClockMs: 0,
      );

      final restored = PlaybackSnapshot.fromJson(snapshot.toJson())!;

      expect(restored.source, isNull);
    });
  });
}
