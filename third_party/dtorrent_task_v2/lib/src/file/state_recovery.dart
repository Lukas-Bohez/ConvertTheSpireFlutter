import 'dart:io';
import 'package:dtorrent_task_v2/src/torrent/torrent_model.dart';
import 'package:logging/logging.dart';
import 'state_file_v2.dart';
import 'file_validator.dart';
import '../piece/piece.dart';
import '../peer/bitfield.dart';

var _log = Logger('StateRecovery');

/// Handles recovery from corrupted or invalid state files
class StateRecovery {
  final TorrentModel metainfo;
  final String savePath;
  final List<Piece> pieces;

  StateRecovery(this.metainfo, this.savePath, this.pieces);

  /// Recover state file from corruption
  ///
  /// This will:
  /// 1. Validate existing state file
  /// 2. If invalid, validate downloaded files
  /// 3. Rebuild bitfield from validated pieces
  /// 4. Create new state file with correct data
  Future<StateFileV2?> recoverStateFile() async {
    try {
      _log.info('Starting state file recovery...');

      // Try to load existing state file
      StateFileV2? stateFile;
      try {
        stateFile = await StateFileV2.getStateFile(savePath, metainfo);
        final isValid = await stateFile.validate();
        if (isValid) {
          _log.info('State file is valid, no recovery needed');
          return stateFile;
        }
        _log.warning('State file validation failed, attempting recovery');
      } catch (e) {
        _log.warning('Failed to load state file, will rebuild from files', e);
      }

      // Validate downloaded files
      final validator = FileValidator(metainfo, pieces, savePath);

      // Quick validation first (check file existence and sizes)
      final quickValid = await validator.quickValidate();
      if (!quickValid) {
        _log.warning(
            'Quick validation failed, some files are missing or have wrong size');
      }

      // Full validation (check piece hashes)
      _log.info('Validating downloaded pieces...');
      final validationResult = await validator.validateAll();

      if (validationResult.error != null) {
        _log.severe('Validation error: ${validationResult.error}');
        return null;
      }

      _log.info(
          'Validation complete: ${validationResult.validatedBytes} / ${validationResult.totalBytes} bytes valid');

      // Rebuild bitfield from validated pieces
      if (metainfo.pieces == null) {
        _log.warning(
            'Cannot recover: torrent has no pieces (v2-only torrent?)');
        return null;
      }
      final bitfield = Bitfield.createEmptyBitfield(metainfo.pieces!.length);
      for (var i = 0; i < pieces.length; i++) {
        if (!validationResult.invalidPieces.contains(i)) {
          // Check if piece is completely written
          if (pieces[i].isCompletelyWritten) {
            bitfield.setBit(i, true);
          }
        }
      }

      // Create new state file with recovered data
      stateFile = StateFileV2(metainfo);
      await stateFile.init(savePath, metainfo);

      // Update bitfield with recovered data
      for (var i = 0; i < bitfield.piecesNum; i++) {
        if (bitfield.getBit(i)) {
          await stateFile.updateBitfield(i, true);
        }
      }

      _log.info('State file recovery completed successfully');
      return stateFile;
    } catch (e, stackTrace) {
      _log.severe('State file recovery failed', e, stackTrace);
      return null;
    }
  }

  /// Recover specific pieces that failed validation
  Future<void> recoverPieces(List<int> invalidPieces) async {
    _log.info('Recovering ${invalidPieces.length} invalid pieces...');

    // Mark pieces as incomplete in state file
    // They will be re-downloaded automatically
    for (var pieceIndex in invalidPieces) {
      if (pieceIndex < pieces.length) {
        // Reset piece state - it will be re-downloaded
        _log.info('Marking piece $pieceIndex for re-download');
      }
    }
  }

  /// Backup existing state file before recovery
  Future<bool> backupStateFile() async {
    try {
      final stateFilePath = '$savePath${metainfo.infoHash}.bt.state';
      final stateFile = File(stateFilePath);

      if (!await stateFile.exists()) {
        return true; // No file to backup
      }

      final backupPath =
          '$stateFilePath.backup.${DateTime.now().millisecondsSinceEpoch}';
      await stateFile.copy(backupPath);

      _log.info('State file backed up to: $backupPath');
      return true;
    } catch (e) {
      _log.warning('Failed to backup state file', e);
      return false;
    }
  }
}
