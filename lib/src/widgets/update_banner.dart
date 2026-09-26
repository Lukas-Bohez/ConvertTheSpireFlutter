import 'package:flutter/material.dart';
import '../services/update_service.dart';
import '../utils/l10n.dart';

class UpdateBanner extends StatelessWidget {
  final UpdateInfo info;
  final VoidCallback onDismiss;
  final VoidCallback onDownload;

  /// The app can install the update itself (Windows, Setup.exe): the button
  /// says Update now instead of Download.
  final bool installsInPlace;

  const UpdateBanner({
    super.key,
    required this.info,
    required this.onDismiss,
    required this.onDownload,
    this.installsInPlace = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.system_update_rounded,
                color: cs.onPrimaryContainer, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.vAvailable(info.latestVersion),
                    style: TextStyle(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  if (info.releaseNotes.isNotEmpty)
                    Text(
                      info.releaseNotes,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onPrimaryContainer
                            .withAlpha((0.8 * 255).round()),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: onDownload,
              style:
                  TextButton.styleFrom(foregroundColor: cs.onPrimaryContainer),
              child: Text(installsInPlace
                  ? context.l10n.updateNow
                  : context.l10n.actionDownload),
            ),
            IconButton(
              icon: Icon(Icons.close, color: cs.onPrimaryContainer, size: 18),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              tooltip: context.l10n.dismiss,
            ),
          ],
        ),
      ),
    );
  }
}
