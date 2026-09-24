import 'package:flutter/material.dart';

import '../models/unified_download_task.dart';
import '../utils/l10n.dart';

enum DownloadProtocolFilter { all, torrents, directHttp }

enum DownloadStatusFilter { all, active, paused, completed }

/// Filter chips + search for lib/src/screens/unified_downloads_screen.dart.
///
/// No special Android TV handling needed here beyond not autofocusing the
/// search field: GlobalCursorOverlay (lib/src/widgets/global_cursor_overlay.dart)
/// already wraps the whole app and drives D-pad input into ordinary
/// Material widgets like FilterChip everywhere else, so this gets that for
/// free as long as it stays built from standard widgets.
class DownloadFilterToolbar extends StatefulWidget {
  final DownloadProtocolFilter protocol;
  final DownloadStatusFilter status;
  final UnifiedDownloadCategory? category;
  final String query;
  final ValueChanged<DownloadProtocolFilter> onProtocolChanged;
  final ValueChanged<DownloadStatusFilter> onStatusChanged;
  final ValueChanged<UnifiedDownloadCategory?> onCategoryChanged;
  final ValueChanged<String> onQueryChanged;

  const DownloadFilterToolbar({
    super.key,
    required this.protocol,
    required this.status,
    required this.category,
    required this.query,
    required this.onProtocolChanged,
    required this.onStatusChanged,
    required this.onCategoryChanged,
    required this.onQueryChanged,
  });

  @override
  State<DownloadFilterToolbar> createState() => _DownloadFilterToolbarState();
}

class _DownloadFilterToolbarState extends State<DownloadFilterToolbar> {
  late final TextEditingController _searchController =
      TextEditingController(text: widget.query);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            // Intentionally no autofocus - on TV this screen is reached
            // via the D-pad cursor, and popping the on-screen keyboard
            // unasked-for on screen entry is exactly the "search bar
            // grabs focus automatically" complaint already raised about
            // the browser's own address bar.
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: context.l10n.searchDownloads,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: widget.onQueryChanged,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _chip(context.l10n.allProtocols, widget.protocol == DownloadProtocolFilter.all,
                  () => widget.onProtocolChanged(DownloadProtocolFilter.all)),
              _chip(context.l10n.tabTorrents, widget.protocol == DownloadProtocolFilter.torrents,
                  () => widget.onProtocolChanged(DownloadProtocolFilter.torrents)),
              _chip(context.l10n.directHttp, widget.protocol == DownloadProtocolFilter.directHttp,
                  () => widget.onProtocolChanged(DownloadProtocolFilter.directHttp)),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _chip(context.l10n.allStatuses, widget.status == DownloadStatusFilter.all,
                  () => widget.onStatusChanged(DownloadStatusFilter.all)),
              _chip(context.l10n.active, widget.status == DownloadStatusFilter.active,
                  () => widget.onStatusChanged(DownloadStatusFilter.active)),
              _chip(context.l10n.paused, widget.status == DownloadStatusFilter.paused,
                  () => widget.onStatusChanged(DownloadStatusFilter.paused)),
              _chip(context.l10n.completed, widget.status == DownloadStatusFilter.completed,
                  () => widget.onStatusChanged(DownloadStatusFilter.completed)),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _chip(context.l10n.allCategories, widget.category == null,
                  () => widget.onCategoryChanged(null)),
              _chip(context.l10n.media, widget.category == UnifiedDownloadCategory.media,
                  () => widget.onCategoryChanged(UnifiedDownloadCategory.media)),
              _chip(context.l10n.appUpdates, widget.category == UnifiedDownloadCategory.appUpdate,
                  () => widget.onCategoryChanged(UnifiedDownloadCategory.appUpdate)),
              _chip(context.l10n.archives, widget.category == UnifiedDownloadCategory.archive,
                  () => widget.onCategoryChanged(UnifiedDownloadCategory.archive)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}
