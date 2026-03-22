import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/search_result.dart';
import '../services/folder_access_service.dart';
import 'quick_download_card.dart';
import 'quick_links_service.dart';

/// Clean home page with a grid of quick-link tiles.
class QuickLinksPage extends StatefulWidget {
  final ValueChanged<String> onNavigate;
  final Future<void> Function(
      SearchResult result, String format, String quality) onDownload;
  final Future<String?> Function() getYtDlpVersion;
  final String? downloadFolder;
  final Future<void> Function()? onPickDownloadFolder;

  const QuickLinksPage({
    super.key,
    required this.onNavigate,
    required this.onDownload,
    required this.getYtDlpVersion,
    this.downloadFolder,
    this.onPickDownloadFolder,
  });

  @override
  State<QuickLinksPage> createState() => _QuickLinksPageState();
}

class _QuickLinksPageState extends State<QuickLinksPage> {
  List<QuickLink> _links = [];
  String? _ytDlpVersion;
  bool _ytDlpChecking = true;
  bool _ytDlpFailed = false;
  bool _isFolderWritable = true;

  @override
  void initState() {
    super.initState();

    _loadLinks();
    _checkYtDlpVersion();
    _validateDownloadFolder();
  }

  @override
  void didUpdateWidget(covariant QuickLinksPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.downloadFolder != widget.downloadFolder) {
      _validateDownloadFolder();
    }
  }

  Future<void> _validateDownloadFolder() async {
    final ok = await FolderAccessService.ensureSafeFolderIsWritable(
      context,
      widget.downloadFolder,
    );
    if (mounted) {
      setState(() => _isFolderWritable = ok);
    }
  }

  String _formatFolderLabel(String path) {
    final p = path.trim();
    if (p.isEmpty) return 'Not set';
    const maxLength = 44;
    if (p.length <= maxLength) return p;
    const segment = 18;
    return '${p.substring(0, segment)}...${p.substring(p.length - segment)}';
  }

  Future<void> _loadLinks() async {
    final links = await QuickLinksService.load();
    if (mounted) setState(() => _links = links);
  }

  Future<void> _checkYtDlpVersion() async {
    setState(() {
      _ytDlpChecking = true;
      _ytDlpFailed = false;
    });
    try {
      final v = await widget.getYtDlpVersion();
      if (mounted) {
        setState(() {
          _ytDlpVersion = v;
          _ytDlpFailed = v == null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _ytDlpFailed = true);
    } finally {
      if (mounted) setState(() => _ytDlpChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width < 500
        ? 2
        : width < 900
            ? 3
            : width < 1200
                ? 4
                : width < 1600
                    ? 5
                    : 6;

    // Filter out only the queue tile (always in sidebar).
    // Browser remains available so users can tap it directly.
    final visibleLinks = _links.where((l) => l.route != 'queue.tab').toList();

    Widget buildHeader() {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: width < 600 ? 20 : 56,
          vertical: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 28),
            // App branding
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          cs.primary.withValues(alpha: 0.15),
                          cs.tertiary.withValues(alpha: 0.10),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(Icons.music_note_rounded,
                        size: 56, color: cs.primary),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Convert the Spire',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: cs.onSurface,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Paste a video or playlist URL below to start downloading.',
                    style: TextStyle(
                      fontSize: 18,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
    }

    Widget buildDownloadSection() {
      final hasFolder = (widget.downloadFolder?.trim().isNotEmpty ?? false);
      final folderLabel =
          _formatFolderLabel(widget.downloadFolder ?? 'Not set');

      final showAndroidReminder = Platform.isAndroid && !hasFolder;

      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: width < 600 ? 20 : 56,
          vertical: Platform.isWindows ? 12 : 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showAndroidReminder)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  'Android: please select your download folder once so permissions remain valid.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            if (!_isFolderWritable)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .errorContainer
                      .withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Download folder became unreachable, please pick it again.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            if (widget.onPickDownloadFolder != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        folderLabel,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        await HapticFeedback.selectionClick();
                        await widget.onPickDownloadFolder?.call();
                      },
                      child: Text(hasFolder ? 'Change' : 'Choose'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            QuickDownloadCard(onDownload: widget.onDownload),
            const SizedBox(height: 12),
            if (!Platform.isAndroid)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.memory,
                    size: 18,
                    color: _ytDlpFailed
                        ? Colors.redAccent
                        : (_ytDlpChecking ? Colors.amber : Colors.green),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _ytDlpChecking
                        ? 'Checking engine...'
                        : _ytDlpFailed
                            ? 'yt-dlp not available (click Settings)'
                            : 'yt-dlp ${_ytDlpVersion ?? 'unknown'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 12),
                  if (_ytDlpFailed)
                    TextButton(
                      onPressed: _checkYtDlpVersion,
                      child: const Text('Retry'),
                    ),
                ],
              ),
          ],
        ),
      );
    }

    return Container(
      color: cs.surfaceContainerLowest,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: buildHeader()),
          SliverToBoxAdapter(child: buildDownloadSection()),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            sliver: _buildLinksGrid(crossAxisCount, visibleLinks),
          ),
        ],
      ),
    );
  }

  Widget _buildLinksGrid(int crossAxisCount, List<QuickLink> visibleLinks) {
    final cs = Theme.of(context).colorScheme;

    if (_links.isEmpty && _ytDlpChecking) {
      return SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => AnimatedOpacity(
              duration: const Duration(milliseconds: 500),
              opacity: 0.7,
              curve: Curves.easeInOut,
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            childCount: crossAxisCount * 2,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.78,
          ),
        ),
      );
    }

    if (_links.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.library_music, size: 64, color: cs.outline),
              const SizedBox(height: 12),
              Text('No media yet',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              FilledButton(
                  onPressed: _loadLinks, child: const Text('Scan library')),
            ],
          ),
        ),
      );
    }

    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (ctx, i) {
          final link = visibleLinks[i];
          return _QuickLinkTile(
            link: link,
            onTap: () {
              FocusScope.of(context).unfocus();
              widget.onNavigate(link.route);
            },
          );
        },
        childCount: visibleLinks.length,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
    );
  }
}

class _QuickLinkTile extends StatefulWidget {
  final QuickLink link;
  final VoidCallback onTap;

  const _QuickLinkTile({required this.link, required this.onTap});

  @override
  State<_QuickLinkTile> createState() => _QuickLinkTileState();
}

class _QuickLinkTileState extends State<_QuickLinkTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: _hovering
              ? cs.primaryContainer.withValues(alpha: 0.35)
              : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hovering
                ? cs.primary.withValues(alpha: 0.3)
                : cs.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(widget.link.icon, color: cs.primary, size: 36),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.link.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  if (widget.link.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.link.description,
                      style: TextStyle(
                        fontSize: 15,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
