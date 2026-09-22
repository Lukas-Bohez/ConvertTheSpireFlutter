import 'dart:io';

import 'package:convert_the_spire_reborn/src/utils/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the process timeout helper.
///
/// Most process calls in the app had no bound at all, and the few that did
/// used `Process.run(...).timeout(...)`, which abandons the future but leaves
/// the child running (issue #7). This helper has to actually kill it.
void main() {
  /// A command that exits immediately, on either platform.
  (String, List<String>) quickCommand() => Platform.isWindows
      ? ('cmd', ['/c', 'echo', 'hello'])
      : ('echo', ['hello']);

  /// A command that runs for several seconds, on either platform.
  (String, List<String>) slowCommand() => Platform.isWindows
      ? ('cmd', ['/c', 'ping', '127.0.0.1', '-n', '10'])
      : ('sleep', ['10']);

  test('a quick command returns its output', () async {
    final (exe, args) = quickCommand();

    final result = await runProcess(exe, args,
        timeout: const Duration(seconds: 30), runInShell: Platform.isWindows);

    expect(result.ok, isTrue, reason: result.stderr);
    expect(result.stdout.trim(), contains('hello'));
    expect(result.timedOut, isFalse);
  });

  test('an overrunning command is killed, not merely abandoned', () async {
    final (exe, args) = slowCommand();

    final watch = Stopwatch()..start();
    final result = await runProcess(exe, args,
        timeout: const Duration(milliseconds: 300),
        runInShell: Platform.isWindows);
    watch.stop();

    expect(result.timedOut, isTrue);
    expect(result.ok, isFalse);
    expect(watch.elapsed, lessThan(const Duration(seconds: 8)),
        reason: 'the helper must not wait for the child to finish');
  });

  test('a missing executable reports instead of throwing', () async {
    final result = await runProcess(
      'definitely-not-a-real-binary-9a8b7c',
      const [],
      timeout: const Duration(seconds: 5),
    );

    expect(result.ok, isFalse);
    expect(result.exitCode, -1);
    expect(result.timedOut, isFalse);
  });
}
