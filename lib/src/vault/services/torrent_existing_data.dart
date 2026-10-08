import 'dart:io';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart' as dt;
// ignore: implementation_imports
import 'package:dtorrent_task_v2/src/piece/piece.dart' as dt_piece;

/// Data of a torrent that is already in [saveDir] before it first starts:
/// a torrent made here from its own files, or one added again for files
/// kept. As qBittorrent does, the files are checked, and the pieces that
/// check out go into the state file the task starts from. The task trusts
/// that file: without one it started at 0%, "Stalled", and could not seed
/// what it had.
///
/// dtorrent's own StateRecovery can't do this: it takes an empty state file
/// for a valid one, and its validator turns down every piece not already
/// marked as written, without reading it.
///
/// Returns the pieces found and the total, or null when there was nothing
/// to check: a state file already there, or not every file on disk at its
/// full size (a download that never started has none of them).
Future<(int have, int total)?> adoptExistingTorrentData(
    dt.TorrentModel model, String saveDir) async {
  final metaPieces = model.pieces;
  if (metaPieces == null || metaPieces.isEmpty || saveDir.isEmpty) {
    return null;
  }
  final dir = saveDir.endsWith(Platform.pathSeparator)
      ? saveDir
      : '$saveDir${Platform.pathSeparator}';
  if (await File('$dir${model.infoHash}.bt.state').exists()) return null;
  final pieces = verifiablePieces(model);
  final validator = dt.FileValidator(model, pieces, dir);
  if (!await validator.quickValidate()) return null;
  final result = await validator.validateAll();
  if (result.error != null) return null;
  final invalid = result.invalidPieces.toSet();
  if (invalid.length == pieces.length) return (0, pieces.length);
  final state = await dt.StateFileV2.getStateFile(dir, model);
  for (var i = 0; i < pieces.length; i++) {
    if (!invalid.contains(i)) await state.updateBitfield(i, true);
  }
  await state.close();
  return (pieces.length - invalid.length, pieces.length);
}

/// The pieces of [model], taken as written so that dtorrent's validator
/// reads and hashes them rather than turning them down unread.
List<dt_piece.Piece> verifiablePieces(dt.TorrentModel model) {
  final metaPieces = model.pieces ?? const [];
  final pieces = <dt_piece.Piece>[];
  var offset = 0;
  for (var i = 0; i < metaPieces.length; i++) {
    final length =
        i == metaPieces.length - 1 ? model.lastPieceLength : model.pieceLength;
    final hash =
        metaPieces[i].map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    pieces.add(dt_piece.Piece(hash, i, length, offset, isComplete: true));
    offset += length;
  }
  return pieces;
}
