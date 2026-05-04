import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:convert_the_spire_reborn/src/services/background_media_update_guard.dart';

void main() {
  group('BackgroundMediaUpdateGuard', () {
    test('tokens increase and older tokens become stale', () {
      final guard = BackgroundMediaUpdateGuard();

      final first = guard.nextToken();
      final second = guard.nextToken();

      expect(second, greaterThan(first));
      expect(guard.isCurrent(first), isFalse);
      expect(guard.isCurrent(second), isTrue);
      expect(guard.currentToken, second);
    });

    test('stale async update is rejected while newest is accepted', () async {
      final guard = BackgroundMediaUpdateGuard();
      String applied = '';

      Future<void> schedule(String label, Duration delay) async {
        final token = guard.nextToken();
        await Future<void>.delayed(delay);
        if (guard.isCurrent(token)) {
          applied = label;
        }
      }

      final oldUpdate = schedule('old', const Duration(milliseconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final newUpdate = schedule('new', const Duration(milliseconds: 5));

      await Future.wait([oldUpdate, newUpdate]);
      expect(applied, 'new');
    });
  });
}
