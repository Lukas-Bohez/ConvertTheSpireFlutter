import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:youtube_explode_dart/solvers.dart';
import 'package:youtube_explode_dart/src/reverse_engineering/challenges/ejs/base_ejs_solver.dart';

/// youtube_explode's Deno solver, made ready in the background.
///
/// The first start downloads Deno (tens of MB), and the app used to show
/// nothing but a spinner until that was done: close to a minute on a slow
/// connection, every start while the download kept failing. Now the app
/// starts at once and the solver follows when Deno is there. YouTube asks
/// that come sooner wait up to 20 seconds for it; when Deno isn't there by
/// then, or can't be had, they fail, and youtube_explode uses the clients
/// that need no solving.
class BackgroundDenoSolver extends BaseEJSSolver {
  BackgroundDenoSolver(Future<String?> denoPath) {
    _solver = denoPath.then<DenoEJSSolver?>((path) async {
      if (path == null) return null;
      final solver = await DenoEJSSolver.init(denoExe: path);
      if (_disposed) {
        solver.dispose();
        return null;
      }
      return solver;
    }).catchError((Object e) {
      debugPrint('BackgroundDenoSolver: Deno solver unavailable: $e');
      return null;
    });
  }

  late final Future<DenoEJSSolver?> _solver;
  bool _disposed = false;

  /// Deletes the temporary folders earlier sessions' solvers left behind.
  ///
  /// DenoEJSSolver makes a `yt_deno_*` folder each start and removes it only
  /// when disposed, which quitting the app skips: one was left in the temp
  /// folder every start. Folders changed in the last 12 hours stay, so a
  /// copy of the app still running keeps its own.
  static Future<void> removeStaleTempDirs({
    @visibleForTesting Directory? parent,
    Duration olderThan = const Duration(hours: 12),
  }) async {
    try {
      final root = parent ?? Directory.systemTemp;
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! Directory ||
            !p.basename(entity.path).startsWith('yt_deno_')) {
          continue;
        }
        final modified = (await entity.stat()).modified;
        if (DateTime.now().difference(modified) < olderThan) continue;
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          // In use or already gone.
        }
      }
    } catch (e) {
      debugPrint('BackgroundDenoSolver: temp cleanup skipped: $e');
    }
  }

  @override
  Future<String> executeJavaScript(String jsCode) async {
    // A download that is still running is not waited out.
    final solver = await _solver.timeout(const Duration(seconds: 20),
        onTimeout: () => null);
    if (solver == null) throw StateError('Deno is not available');
    return solver.executeJavaScript(jsCode);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_solver.then((solver) => solver?.dispose()));
  }
}
