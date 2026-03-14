import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/snack.dart';

import 'dart:io' show File, Platform;

import '../services/dlna_control_service.dart';
import '../services/dlna_discovery_service.dart';
import '../services/local_media_server.dart';
import '../services/platform_dirs.dart';

/// A dialog that discovers DLNA devices on the network and allows the user
/// to cast a local media file to a selected device.
///
/// Usage:
/// ```dart
/// CastDialog.show(
///   context: context,
///   filePath: '/path/to/video.mp4',
///   title: 'My Video',
/// );
/// ```
class CastDialog extends StatefulWidget {
  final String filePath;
  final String title;

  const CastDialog({
    super.key,
    required this.filePath,
    required this.title,
  });

  /// Show the cast dialog as a modal bottom sheet.
  static Future<void> show({
    required BuildContext context,
    required String filePath,
    String title = 'Cast to device',
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => CastDialog(filePath: filePath, title: title),
    );
  }

  @override
  State<CastDialog> createState() => _CastDialogState();
}

class _CastDialogState extends State<CastDialog> {
  final DlnaDiscoveryService _discovery = DlnaDiscoveryService();
  final DlnaControlService _control = DlnaControlService();
  final LocalMediaServer _server = LocalMediaServer();
  String? _tempServedPath;

  List<DlnaDevice>? _devices;
  bool _scanning = false;
  String? _error;
  DlnaDevice? _castingTo;
  bool _isCasting = false;
  bool _showManualInput = false;
  final TextEditingController _manualIpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _manualIpController.dispose();
    // Don't stop the server on dispose — it needs to stay alive while casting
    super.dispose();
  }

  Future<void> _startScan() async {
    final isRescan = _devices != null;
    setState(() {
      _scanning = true;
      _error = null;
      if (!isRescan) _devices = null;
    });

    try {
      final devices = await _discovery.discover(
        timeout: const Duration(seconds: 5),
      );
      if (mounted) {
        setState(() {
          // Merge new devices with existing (dedup by udn)
          final existing = {
            for (final d in _devices ?? <DlnaDevice>[]) d.udn: d
          };
          for (final d in devices) {
            existing.putIfAbsent(d.udn, () => d);
          }
          _devices = existing.values.toList();
          _scanning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _error = 'Discovery failed: $e';
          _devices = [];
        });
      }
    }
  }

  Future<void> _castToDevice(DlnaDevice device) async {
    setState(() {
      _castingTo = device;
      _isCasting = true;
      _error = null;
    });

    try {
      // 1. Get local IP
      final localIp = await LocalMediaServer.getLocalIp();
      if (localIp == null) {
        throw Exception(
          'Could not determine local IP address. '
          'Ensure you are connected to a Wi-Fi or LAN network.',
        );
      }

      // 2. Prepare file for serving: if on Android and the path is a
      // content:// URI (SAF/MediaStore), copy it into cache so dart:io can
      // stream it to DLNA devices.
      String servePath = widget.filePath;
      if (!kIsWeb && Platform.isAndroid && servePath.startsWith('content://')) {
        final copied = await PlatformDirs.copyToTemp(servePath);
        if (copied == null) throw Exception('Failed to prepare file for casting');
        servePath = copied;
        _tempServedPath = copied;
      }

      // 3. Start the local HTTP server
      final mediaUrl = await _server.serve(
        filePath: servePath,
        localIp: localIp,
      );

      // 3. Determine MIME type
      final ext = widget.filePath.split('.').last.toLowerCase();
      final mimeType = switch (ext) {
        'mp4' => 'video/mp4',
        'mkv' => 'video/x-matroska',
        'avi' => 'video/x-msvideo',
        'webm' => 'video/webm',
        'mp3' => 'audio/mpeg',
        'm4a' => 'audio/mp4',
        'flac' => 'audio/flac',
        'wav' => 'audio/wav',
        _ => 'video/mp4',
      };

      // 4. Send play command to the TV
      await _control.playMedia(
        device: device,
        mediaUrl: mediaUrl,
        title: widget.title,
        mimeType: mimeType,
      );

      if (mounted) {
        setState(() {
          _isCasting = false;
        });
        _showCastingControls(device);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCasting = false;
          _error = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _connectManualIp() async {
    final ip = _manualIpController.text.trim();
    if (ip.isEmpty) return;

    setState(() {
      _scanning = true;
      _error = null;
    });

    try {
      final device = await _discovery.discoverByIp(ip);
      if (device != null && mounted) {
        setState(() {
          _scanning = false;
          _devices = [...?_devices, device];
          _showManualInput = false;
        });
      } else {
        setState(() {
          _scanning = false;
          _error = 'Could not find a DLNA device at $ip';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _error = 'Failed to connect: $e';
        });
      }
    }
  }

  void _showCastingControls(DlnaDevice device) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.cast_connected, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(child: Text('Casting to ${device.name}')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.pause_circle, size: 40),
                  onPressed: () async {
                    try {
                      await _control.pause(device);
                    } catch (e) {
                      if (ctx.mounted) {
                        Snack.show(ctx, 'Pause failed: $e',
                            level: SnackLevel.error);
                      }
                    }
                  },
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.play_circle, size: 40),
                  onPressed: () async {
                    try {
                      await _control.play(device);
                    } catch (e) {
                      if (ctx.mounted) {
                        Snack.show(ctx, 'Play failed: $e',
                            level: SnackLevel.error);
                      }
                    }
                  },
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.stop_circle, size: 40),
                    onPressed: () async {
                    try {
                      await _control.stop(device);
                      await _server.stop();
                      if (_tempServedPath != null) {
                        try {
                          final f = File(_tempServedPath!);
                          if (await f.exists()) await f.delete();
                        } catch (_) {}
                        _tempServedPath = null;
                      }
                    } catch (_) {}
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await _control.stop(device);
                await _server.stop();
                if (_tempServedPath != null) {
                  try {
                    final f = File(_tempServedPath!);
                    if (await f.exists()) await f.delete();
                  } catch (_) {}
                  _tempServedPath = null;
                }
              } catch (_) {}
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 500),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.cast, color: cs.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Cast to Device',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (!_scanning)
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Rescan',
                    onPressed: _startScan,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'File: ${widget.title}',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Divider(),

            // Error banner
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: cs.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style:
                            TextStyle(color: cs.onErrorContainer, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Scanning indicator
            if (_scanning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Scanning for devices…'),
                    ],
                  ),
                ),
              )
            else if (_devices != null && _devices!.isEmpty && !_showManualInput)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.devices_other, size: 48, color: cs.outline),
                      const SizedBox(height: 8),
                      const Text('No devices found'),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _startScan,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Rescan'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () =>
                                setState(() => _showManualInput = true),
                            icon: const Icon(Icons.edit),
                            label: const Text('Enter IP'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else if (_devices != null) ...[
              // Scanning progress bar
              if (_scanning && _devices != null)
                const LinearProgressIndicator(),

              // Device list
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _devices!.length,
                  itemBuilder: (_, index) {
                    final device = _devices![index];
                    final isCastTarget =
                        _castingTo != null && _castingTo!.udn == device.udn;
                    return ListTile(
                      leading: Icon(
                        device.deviceType.icon,
                        color:
                            device.isPanasonicViera ? Colors.blue : cs.primary,
                      ),
                      title: Text(device.name),
                      subtitle: Text(
                        device.isPanasonicViera
                            ? 'Panasonic Viera • ${device.address.address}'
                            : '${device.deviceType.name} • ${device.address.address}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: isCastTarget && _isCasting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.play_arrow, color: cs.primary),
                      onTap: _isCasting ? null : () => _castToDevice(device),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              // Manual IP button below device list
              if (!_showManualInput)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _showManualInput = true),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Enter IP manually'),
                  ),
                ),
            ],

            // Manual IP input
            if (_showManualInput) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualIpController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Device IP address',
                        hintText: '192.168.1.100',
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onSubmitted: (_) => _connectManualIp(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _connectManualIp,
                    child: const Text('Connect'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
