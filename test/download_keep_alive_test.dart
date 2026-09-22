import 'package:convert_the_spire_reborn/src/services/download_keep_alive.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the foreground-service ref counting.
///
/// Downloads used to stop whenever the phone locked, because nothing ever
/// started a foreground service (issue #7). These tests pin the part that
/// decides when it runs: start on the first piece of work, stop only after the
/// queue has really finished, and do not hammer the notification in between.
void main() {
  late List<String> events;
  late DownloadKeepAlive keepAlive;

  setUp(() {
    events = [];
    keepAlive = DownloadKeepAlive.forTest(
      start: (text, progress) async => events.add('start:$text:$progress'),
      update: (text, progress) async => events.add('update:$text:$progress'),
      stop: () async => events.add('stop'),
    );
  });

  test('starts the service when work appears', () {
    keepAlive.report(active: 1, text: 'One song', progress: 10);

    expect(events, ['start:One song:10']);
    expect(keepAlive.isServiceRunning, isTrue);
  });

  test('does not start again while work continues', () {
    keepAlive.report(active: 1, text: 'One song', progress: 10);
    keepAlive.report(active: 2, text: 'Two items', progress: 20);

    expect(events, ['start:One song:10', 'update:Two items:20']);
  });

  test('skips updates that would say exactly the same thing', () {
    keepAlive.report(active: 1, text: 'One song', progress: 10);
    keepAlive.report(active: 1, text: 'One song', progress: 10);

    expect(events, ['start:One song:10']);
  });

  test('throttles updates to the configured interval', () {
    keepAlive.updateInterval = const Duration(minutes: 1);
    keepAlive.report(active: 1, text: 'One song', progress: 10);
    keepAlive.report(active: 1, text: 'One song', progress: 11);
    keepAlive.report(active: 1, text: 'One song', progress: 12);

    expect(events, ['start:One song:10'],
        reason: 'progress ticks many times a second during a download');
  });

  test('stopping is debounced, so a gap between items keeps it alive',
      () async {
    keepAlive.report(active: 1, text: 'One song', progress: 10);
    keepAlive.report(active: 0, text: 'Finishing up');
    keepAlive.report(active: 1, text: 'Next song', progress: 0);

    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(events, ['start:One song:10', 'update:Next song:0']);
    expect(keepAlive.isServiceRunning, isTrue);
  });

  test('stops once the queue stays empty', () async {
    keepAlive.report(active: 1, text: 'One song', progress: 10);
    keepAlive.report(active: 0, text: 'Finishing up');

    expect(events, ['start:One song:10'], reason: 'not stopped immediately');

    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(events, ['start:One song:10', 'stop']);
    expect(keepAlive.isServiceRunning, isFalse);
  });

  test('stopNow cuts the service without waiting for the debounce', () async {
    keepAlive.report(active: 3, text: 'Three items', progress: -1);
    await keepAlive.stopNow();

    expect(events, ['start:Three items:-1', 'stop']);
    expect(keepAlive.activeCount, 0);
  });

  test('stopNow on an idle keep-alive does nothing', () async {
    await keepAlive.stopNow();

    expect(events, isEmpty);
  });

  test('a negative count is treated as no work', () async {
    keepAlive.report(active: 1, text: 'One song', progress: 10);
    keepAlive.report(active: -5, text: 'Finishing up');

    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(events, ['start:One song:10', 'stop']);
  });
}
