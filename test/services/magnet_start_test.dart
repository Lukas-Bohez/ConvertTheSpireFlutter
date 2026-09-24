import 'package:convert_the_spire_reborn/src/vault/bittorrent/info_hash.dart';
import 'package:convert_the_spire_reborn/src/vault/bittorrent/magnet_link.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_service.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart' as dt;
import 'package:flutter_test/flutter_test.dart';

/// A nyaa magnet reported as "Stalled 0.0%" forever: base32 info-hash, a
/// dozen trackers, one of them WebTorrent-only.
const _nyaaMagnet =
    'magnet:?xt=urn:btih:FUN4WSJQXBSHMQDOUAMBG7AKIZHOODQV'
    '&dn=%5BSubsPlease%5D%20Re%20Zero%20kara%20Hajimeru%20Isekai%20Seikatsu%20-%2084%20%281080p%29%20%5B5188BBC4%5D.mkv'
    '&xl=1449305708'
    '&tr=http%3A%2F%2Fnyaa.tracker.wf%3A7777%2Fannounce'
    '&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce'
    '&tr=udp%3A%2F%2Fopen.stealth.si%3A80%2Fannounce'
    '&tr=udp%3A%2F%2Fexodus.desync.com%3A6969%2Fannounce'
    '&tr=udp%3A%2F%2Ftracker.torrent.eu.org%3A451%2Fannounce'
    '&tr=http%3A%2F%2Ftracker.mywaifu.best%3A6969%2Fannounce'
    '&tr=https%3A%2F%2Ftracker.zhuqiy.com%3A443%2Fannounce'
    '&tr=udp%3A%2F%2Ftracker.tryhackx.org%3A6969%2Fannounce'
    '&tr=udp%3A%2F%2Fretracker.hotplug.ru%3A2710%2Fannounce'
    '&tr=udp%3A%2F%2Ftracker.dler.com%3A6969%2Fannounce'
    '&tr=http%3A%2F%2Ftracker.beeimg.com%3A6969%2Fannounce'
    '&tr=udp%3A%2F%2Ft.overflow.biz%3A6969%2Fannounce'
    '&tr=wss%3A%2F%2Ftracker.openwebtorrent.com';

/// The same hash in hex, as `python -c "base64.b32decode(...).hex()"` gives.
const _nyaaHex = '2d1bcb4930b86476406ea018137c0a464ee70e15';

void main() {
  group('InfoHash', () {
    test('turns a base32 info-hash into the hex one', () {
      expect(InfoHash.normalizeBtih('FUN4WSJQXBSHMQDOUAMBG7AKIZHOODQV'),
          _nyaaHex);
      expect(InfoHash.normalizeBtih('fun4wsjqxbshmqdouambg7akizhoodqv'),
          _nyaaHex);
    });

    test('keeps a hex info-hash, lowercased', () {
      expect(InfoHash.normalizeBtih(_nyaaHex.toUpperCase()), _nyaaHex);
    });

    test('rejects anything else', () {
      expect(InfoHash.normalizeBtih('not-a-hash'), isNull);
      expect(InfoHash.normalizeBtih('0189'), isNull);
    });

    test('reads the bytes of old base32 ids and new hex ids alike', () {
      final fromBase32 = InfoHash.bytesOf('FUN4WSJQXBSHMQDOUAMBG7AKIZHOODQV');
      final fromHex = InfoHash.bytesOf(_nyaaHex);
      expect(fromBase32, isNotNull);
      expect(fromBase32, hasLength(20));
      expect(fromBase32, fromHex);
    });

    test('lists the trackers the engine can use, in order, without wss', () {
      final trackers = InfoHash.magnetTrackers(_nyaaMagnet);
      expect(trackers, hasLength(12));
      expect(trackers.first, 'http://nyaa.tracker.wf:7777/announce');
      expect(trackers, contains('udp://tracker.opentrackr.org:1337/announce'));
      expect(trackers, contains('https://tracker.zhuqiy.com:443/announce'));
      expect(trackers.any((t) => t.startsWith('wss:')), isFalse);
    });

    test('reads tiered tr.N trackers and drops duplicates', () {
      const magnet = 'magnet:?xt=urn:btih:$_nyaaHex'
          '&tr.1=udp%3A%2F%2Fa.example%3A1%2Fannounce'
          '&tr=udp%3A%2F%2Fa.example%3A1%2Fannounce'
          '&tr.2=http%3A%2F%2Fb.example%2Fannounce';
      expect(InfoHash.magnetTrackers(magnet), [
        'udp://a.example:1/announce',
        'http://b.example/announce',
      ]);
    });
  });

  group('MagnetLink', () {
    test('stores a base32 magnet under the hex info-hash', () {
      final magnet = MagnetLink.parse(_nyaaMagnet);
      expect(magnet.infoHashV1, _nyaaHex);
      expect(magnet.displayName,
          '[SubsPlease] Re Zero kara Hajimeru Isekai Seikatsu - 84 (1080p) [5188BBC4].mkv');
      expect(magnet.trackers, contains('http://nyaa.tracker.wf:7777/announce'));
    });

    test('gives the same id whichever way the hash is written', () {
      final base32 = MagnetLink.parse(_nyaaMagnet);
      final hex = MagnetLink.parse('magnet:?xt=urn:btih:$_nyaaHex');
      expect(base32.infoHashV1, hex.infoHashV1);
    });
  });

  group('engine magnet', () {
    test('keeps the link\'s own trackers for the metadata download', () {
      final engineMagnet =
          InfoHash.engineMagnet(_nyaaHex, sourceMagnet: _nyaaMagnet);
      final parsed = dt.MagnetParser.parse(engineMagnet);
      expect(parsed, isNotNull);
      expect(InfoHash.toHex(parsed!.infoHash), _nyaaHex);
      final trackers = parsed.trackers.map((u) => u.toString()).toList();
      expect(trackers, contains('http://nyaa.tracker.wf:7777/announce'));
      expect(trackers, contains('udp://tracker.opentrackr.org:1337/announce'));
      expect(trackers, hasLength(12));
    });

    test('survives a display name the strict parser would choke on', () {
      const messy = 'magnet:?xt=urn:btih:$_nyaaHex&dn=100%25 & more %zz'
          '&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce';
      final parsed = dt.MagnetParser.parse(
          InfoHash.engineMagnet(_nyaaHex, sourceMagnet: messy));
      expect(parsed, isNotNull);
      expect(parsed!.trackers, hasLength(1));
    });

    test('works without a source link', () {
      final parsed = dt.MagnetParser.parse(InfoHash.engineMagnet(_nyaaHex));
      expect(parsed, isNotNull);
      expect(parsed!.trackers, isEmpty);
    });
  });

  group('status while the file list is fetched', () {
    test('reads "Fetching Metadata", not "Stalled"', () {
      expect(
        TorrentService.statusLabelForTesting('downloading',
            fetchingMetadata: true),
        TorrentService.fetchingMetadataLabel,
      );
      expect(TorrentService.statusLabelForTesting('downloading'), 'Stalled');
      expect(
        TorrentService.statusLabelForTesting('downloading',
            downloadSpeed: 4096),
        'Downloading',
      );
    });

    test('a paused torrent stays paused while metadata is pending', () {
      expect(
        TorrentService.statusLabelForTesting('paused', fetchingMetadata: true),
        'Paused',
      );
    });

    test('says how many peers are sending the file list', () {
      expect(
        TorrentService.statusMessageForTesting(
            'downloading', TorrentService.fetchingMetadataLabel,
            peers: 3),
        contains('3 peers'),
      );
      expect(
        TorrentService.statusMessageForTesting(
            'downloading', TorrentService.fetchingMetadataLabel),
        contains('Looking for peers'),
      );
    });
  });
}
