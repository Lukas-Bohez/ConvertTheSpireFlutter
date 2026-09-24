import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What a [runProcess] call produced.
class ProcessRunResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  /// True when the process was killed for running past its timeout.
  final bool timedOut;

  const ProcessRunResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
  });

  /// True when the process finished on its own with a success code.
  bool get ok => !timedOut && exitCode == 0;
}

/// Runs a process under a hard timeout, killing it if it overruns.
///
/// `Process.run(...).timeout(...)` only abandons the future: the child keeps
/// running, holding file handles and CPU. Most of the app's process calls had
/// no bound at all, which is the same bug class as the refresh hang in issue
/// #7 - a subprocess that never returns froze whatever was waiting on it.
///
/// Never throws for an overrun; the result carries [ProcessRunResult.timedOut]
/// so callers can decide, and a probe that fails is usually just "not here".
Future<ProcessRunResult> runProcess(
  String executable,
  List<String> arguments, {
  required Duration timeout,
  String? workingDirectory,
  Map<String, String>? environment,
  bool runInShell = false,
}) async {
  final Process process;
  try {
    process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: runInShell,
    );
  } on ProcessException catch (e) {
    return ProcessRunResult(
      exitCode: -1,
      stdout: '',
      stderr: e.message,
    );
  }

  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();
  final drained = <Future<void>>[
    process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .forEach(stdoutBuffer.write),
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .forEach(stderrBuffer.write),
  ];

  var timedOut = false;
  final exitCode = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      timedOut = true;
      // SIGKILL rather than SIGTERM: this is already the unhappy path, and a
      // child that ignores a polite signal is exactly the one causing trouble.
      process.kill(ProcessSignal.sigkill);
      return process.exitCode;
    },
  );

  // Let whatever the process managed to emit land before reporting.
  try {
    await Future.wait(drained).timeout(const Duration(seconds: 2));
  } on TimeoutException {
    // Streams of a killed process can stay open; the partial output is fine.
  }

  return ProcessRunResult(
    exitCode: exitCode,
    stdout: stdoutBuffer.toString(),
    stderr: stderrBuffer.toString(),
    timedOut: timedOut,
  );
}
