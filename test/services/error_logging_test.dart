import 'dart:io';

import 'package:convert_the_spire_reborn/src/services/error_log.dart';
import 'package:convert_the_spire_reborn/src/services/session_log_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// An app left running (a torrent seeding for an hour) with an error every
/// few seconds used to write each one in full to startup_errors.log, a
/// minidump of itself on Windows, and its whole session log again. These
/// keep that small.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('error_logging_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
  });

  tearDown(() => dir.delete(recursive: true));

  group('ErrorLog', () {
    test('writes an error in full a few times, then only its count', () async {
      final file = File('${dir.path}/startup_errors.log');
      final log = ErrorLog(file);
      for (var i = 0; i < 1000; i++) {
        log.record('ZONE ERROR', const SocketException('Connection reset'),
            StackTrace.current);
      }
      await log.idle;
      final text = await file.readAsString();
      expect('ZONE ERROR:'.allMatches(text).length, 3);
      expect(text, contains('10 times this session'));
      expect(text, contains('100 times this session'));
      expect(text, contains('1000 times this session'));
      expect(text, isNot(contains('11 times')));
    });

    test('moves the file aside when it gets too big', () async {
      final file = File('${dir.path}/startup_errors.log');
      final log = ErrorLog(file, maxBytes: 2000, fullRepeats: 1000);
      for (var i = 0; i < 50; i++) {
        log.record('ZONE ERROR', 'error $i', StackTrace.current);
      }
      await log.idle;
      expect(await file.length(), lessThan(4000));
      expect(File('${dir.path}/startup_errors.old.log').existsSync(), isTrue);
    });
  });

  group('SessionLogService', () {
    test('keeps the startup and the latest marks, not every one', () {
      final log = SessionLogService.instance..start();
      for (var i = 0; i < 5000; i++) {
        log.mark('mark $i');
      }
      final recent = log.recent(limit: 100000);
      expect(recent.length, lessThan(600));
      expect(recent.first, contains('session_start'));
      expect(recent.last, contains('mark 4999'));
    });

    test('a flush appends only what is new', () async {
      final log = SessionLogService.instance..start();
      log.mark('before first flush');
      final path = (await log.flush('one'))!;
      log.mark('before second flush');
      await log.flush('two');
      final text = await File(path).readAsString();
      expect('before first flush'.allMatches(text).length, 1);
      expect('before second flush'.allMatches(text).length, 1);
    });
  });
}
