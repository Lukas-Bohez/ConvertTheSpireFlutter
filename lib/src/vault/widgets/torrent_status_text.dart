import 'package:flutter/widgets.dart';

import '../../utils/l10n.dart';
import '../services/torrent_service.dart';

/// The torrent status label from [TorrentService] in the app's language.
///
/// The service works in fixed English labels because other code compares
/// them; this translates them only for display. Anything unrecognised is
/// shown as it is.
String localizedTorrentStatus(BuildContext context, String label) {
  final l10n = context.l10n;
  switch (label) {
    case 'Downloading':
      return l10n.downloading;
    case 'Queued':
      return l10n.queued;
    case 'Paused':
      return l10n.paused;
    case 'Error':
      return l10n.commonError;
    case 'Seeding':
      return l10n.torrentStatusSeeding;
    case 'Seeding partial':
      return l10n.torrentStatusSeedingPartial;
    case 'Stalled':
      return l10n.torrentStatusStalled;
    case 'Checking':
      return l10n.torrentStatusChecking;
    case 'Pending Metadata':
      return l10n.torrentStatusPendingMetadata;
    case TorrentService.fetchingMetadataLabel:
      return l10n.torrentStatusFetchingMetadata;
    case 'File In Use':
      return l10n.torrentStatusFileInUse;
    case 'Missing Files':
      return l10n.torrentStatusMissingFiles;
  }
  return label;
}
