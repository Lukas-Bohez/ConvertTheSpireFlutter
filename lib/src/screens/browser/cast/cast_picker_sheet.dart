import 'package:flutter/material.dart';

import '../../../browser/cast/cast_service.dart';
import '../../../browser/cast/unified_cast_service.dart';

/// Bottom sheet picker showing detected video URLs and discovered cast devices.
class CastPickerSheet extends StatefulWidget {
  final Set<String> detectedUrls;
  final UnifiedCastService castService;
  final void Function(CastDevice device, String url) onCast;

  const CastPickerSheet({
    super.key,
    required this.detectedUrls,
    required this.castService,
    required this.onCast,
  });

  @override
  State<CastPickerSheet> createState() => _CastPickerSheetState();
}

class _CastPickerSheetState extends State<CastPickerSheet> {
  String? _selectedUrl;
  CastDevice? _selectedDevice;

  @override
  void initState() {
    super.initState();
    if (widget.detectedUrls.isNotEmpty) {
      _selectedUrl = widget.detectedUrls.first;
    }
    widget.castService.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.castService.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final devices = widget.castService.discoveredDevices;
    final urls = widget.detectedUrls.toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      maxChildSize: 0.85,
      minChildSize: 0.3,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('Cast Media',
                style: Theme.of(context).textTheme.titleMedium),
            const Divider(),

            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // ── Detected videos ──
                  if (urls.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.videocam_off,
                                size: 48,
                                color:
                                    cs.onSurfaceVariant.withValues(alpha: 0.5)),
                            const SizedBox(height: 8),
                            Text('No video streams detected',
                                style: TextStyle(
                                    color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    Text('Detected Videos',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 4),
                    ...urls.map((url) {
                      final isSelected = url == _selectedUrl;
                      return ListTile(
                        dense: true,
                        // ignore: deprecated_member_use
                        leading: Radio<String>(
                          value: url,
                          groupValue: _selectedUrl,
                          onChanged: (v) =>
                              setState(() => _selectedUrl = v),
                        ),
                        title: Text(
                          _truncateUrl(url),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          _mediaTypeLabel(url),
                          style: TextStyle(
                            fontSize: 11,
                            color: isSelected
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        onTap: () =>
                            setState(() => _selectedUrl = url),
                      );
                    }),
                  ],

                  const Divider(height: 24),

                  // ── Devices ──
                  Text('Cast Devices',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),

                  if (devices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Text('Searching for devices…',
                              style: TextStyle(
                                  color: cs.onSurfaceVariant)),
                        ],
                      ),
                    )
                  else
                    ...devices.map((device) {
                      final isSelected = device == _selectedDevice;
                      return ListTile(
                        dense: true,
                        // ignore: deprecated_member_use
                        leading: Radio<CastDevice>(
                          value: device,
                          groupValue: _selectedDevice,
                          onChanged: (v) =>
                              setState(() => _selectedDevice = v),
                        ),
                        title: Text(device.name),
                        subtitle: Text(
                          device.type == CastDeviceType.chromecast
                              ? 'Chromecast'
                              : 'DLNA / UPnP',
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        trailing: Icon(
                          device.type == CastDeviceType.chromecast
                              ? Icons.cast
                              : Icons.tv,
                          color: isSelected ? cs.primary : null,
                        ),
                        onTap: () =>
                            setState(() => _selectedDevice = device),
                      );
                    }),
                ],
              ),
            ),

            // ── Cast button ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (_selectedUrl != null && _selectedDevice != null)
                      ? () =>
                          widget.onCast(_selectedDevice!, _selectedUrl!)
                      : null,
                  icon: const Icon(Icons.cast),
                  label: const Text('Cast Selected Video'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _truncateUrl(String url) {
    if (url.length <= 80) return url;
    return '${url.substring(0, 40)}…${url.substring(url.length - 35)}';
  }

  String _mediaTypeLabel(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8')) return 'HLS Stream';
    if (lower.contains('.mpd')) return 'DASH Stream';
    if (lower.contains('.mp4')) return 'MP4 Video';
    if (lower.contains('.webm')) return 'WebM Video';
    if (lower.contains('.mkv')) return 'MKV Video';
    return 'Video Stream';
  }
}
