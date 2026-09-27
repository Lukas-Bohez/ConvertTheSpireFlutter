import 'package:convert_the_spire_reborn/src/vault/services/settings_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_engine_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The seeding limit in Settings stops a finished torrent's seeding. A
/// torrent it stopped said "Seeding" all the same, and Resume did nothing:
/// the limit paused it again at once.
void main() {
  final settings = SettingsService.instance;
  late bool allowSeeding;
  late double cap;

  setUp(() {
    allowSeeding = settings.allowSeedingAfterComplete;
    cap = settings.maxSeedingRatio;
    settings.allowSeedingAfterComplete = true;
    settings.maxSeedingRatio = 1.5;
  });
  tearDown(() {
    settings.allowSeedingAfterComplete = allowSeeding;
    settings.maxSeedingRatio = cap;
  });

  String? stopReason(double? ownCap, double ratio) =>
      TorrentEngineService.seedingStopReasonForTesting(ownCap, ratio);

  group('seeding limit', () {
    test('stops at the ratio in Settings', () {
      expect(stopReason(null, 1.49), isNull);
      expect(stopReason(null, 1.5), contains('1.50'));
    });

    test('no ratio in Settings means no limit', () {
      settings.maxSeedingRatio = 0;
      expect(stopReason(null, 50), isNull);
    });

    test('seeding switched off stops it', () {
      settings.allowSeedingAfterComplete = false;
      expect(stopReason(null, 0), isNotNull);
    });

    test('a torrent resumed past the limit keeps seeding', () {
      // keepSeedingIfLimitReached gives it its own limit of 0: none.
      expect(stopReason(0, 5), isNull);
      settings.allowSeedingAfterComplete = false;
      expect(stopReason(0, 5), isNull);
    });

    test('a torrent\'s own limit wins over the one in Settings', () {
      expect(stopReason(3, 2), isNull);
      expect(stopReason(3, 3), isNotNull);
    });
  });

  group('shown state', () {
    final service = TorrentService.instance;

    test('a paused finished torrent reads "paused", not "seeding"', () {
      expect(
        service.deriveStateForTesting('seeding', 'paused', true,
            hasRuntime: true),
        'paused',
      );
      // Not running yet after a restart.
      expect(service.deriveStateForTesting('paused', null, true), 'paused');
    });

    test('a finished torrent that runs is seeding', () {
      expect(
        service.deriveStateForTesting('paused', 'seeding', true,
            hasRuntime: true),
        'seeding',
      );
      expect(service.deriveStateForTesting('seeding', null, true), 'seeding');
    });
  });
}
