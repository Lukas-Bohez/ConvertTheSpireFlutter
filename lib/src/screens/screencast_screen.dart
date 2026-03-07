import 'dart:async';

import 'package:flutter/material.dart';

import '../services/dlna_discovery_service.dart';
import '../services/screencast_service.dart';

/// Tab that lets the user stream their entire screen + audio to a
/// Chromecast / DLNA Android TV on the local network.
class ScreencastScreen extends StatefulWidget {
  const ScreencastScreen({super.key});

  @override
  State<ScreencastScreen> createState() => _ScreencastScreenState();
}

class _ScreencastScreenState extends State<ScreencastScreen>
    with AutomaticKeepAliveClientMixin {
  final ScreencastService _service = ScreencastService();

  List<DlnaDevice>? _devices;
  bool _scanning = false;
  String? _scanError;
  bool _showManualIp = false;
  final _ipController = TextEditingController();

  // Stream settings
  int _resolution = 1080; // 720 or 1080
  int _framerate = 30;

  @override
  void initState() {
    super.initState();
    _service.onStateChanged = () {
      if (mounted) setState(() {});
    };
    if (ScreencastService.isSupported) _startScan();
  }

  @override
  void dispose() {
    _service.onStateChanged = null;
    _service.dispose();
    _ipController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _scanError = null;
    });
    try {
      final devices = await _service.discoverDevices();
      if (mounted) {
        setState(() {
          _devices = devices;
          _scanning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _scanError = e.toString();
          _devices = [];
        });
      }
    }
  }

  Future<void> _addManualIp() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;
    setState(() => _scanning = true);
    try {
      final device = await _service.discoverByIp(ip);
      if (device != null && mounted) {
        setState(() {
          _devices = [...?_devices, device];
          _showManualIp = false;
          _scanning = false;
          _ipController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _scanError = 'Could not find device at $ip';
        });
      }
    }
  }

  Future<void> _startCast(DlnaDevice device) async {
    final w = _resolution == 720 ? 1280 : 1920;
    final h = _resolution;
    await _service.startCast(
      device: device,
      width: w,
      height: h,
      framerate: _framerate,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!ScreencastService.isSupported) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cast, size: 64, color: cs.outline),
              const SizedBox(height: 16),
              Text('Screen Cast',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              Text(
                'Screen casting is available on Android, Windows, and Linux.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.outline),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Header ─────────────────────────────────────
        _buildHeader(cs, theme),
        const SizedBox(height: 16),

        // ── Active cast card ───────────────────────────
        if (_service.state != ScreencastState.idle) ...[
          _buildActiveCastCard(cs),
          const SizedBox(height: 16),
        ],

        // ── Settings card ──────────────────────────────
        _buildSettingsCard(cs),
        const SizedBox(height: 16),

        // ── Device list ────────────────────────────────
        _buildDeviceList(cs, theme),
      ],
    );
  }

  Widget _buildHeader(ColorScheme cs, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.cast, size: 32, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Screen Cast',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    'Stream your entire screen with audio to any Chromecast or DLNA TV on your network.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveCastCard(ColorScheme cs) {
    final state = _service.state;
    final device = _service.castingTo;

    return Card(
      color: state == ScreencastState.error
          ? cs.errorContainer.withValues(alpha: 0.3)
          : cs.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                if (state == ScreencastState.streaming)
                  Icon(Icons.cast_connected, color: Colors.green, size: 28)
                else if (state == ScreencastState.error)
                  Icon(Icons.error_outline, color: cs.error, size: 28)
                else
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state == ScreencastState.streaming
                            ? 'Casting to ${device?.name ?? 'device'}'
                            : state == ScreencastState.starting
                                ? 'Connecting\u2026'
                                : state == ScreencastState.stopping
                                    ? 'Stopping\u2026'
                                    : 'Error',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      if (state == ScreencastState.streaming)
                        Text(
                          '${_resolution}p @ ${_framerate}fps \u2022 Full HD + Audio',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      if (_service.lastError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(_service.lastError!,
                              style:
                                  TextStyle(color: cs.error, fontSize: 12)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (state == ScreencastState.streaming ||
                state == ScreencastState.error) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _service.stopCast(),
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop Casting'),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                const Text('Stream Settings',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                    child: Text('Resolution', style: TextStyle(fontSize: 13))),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 720, label: Text('720p')),
                    ButtonSegment(value: 1080, label: Text('1080p')),
                  ],
                  selected: {_resolution},
                  onSelectionChanged: _service.isStreaming
                      ? null
                      : (v) => setState(() => _resolution = v.first),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                    child: Text('Frame Rate', style: TextStyle(fontSize: 13))),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 24, label: Text('24')),
                    ButtonSegment(value: 30, label: Text('30')),
                    ButtonSegment(value: 60, label: Text('60')),
                  ],
                  selected: {_framerate},
                  onSelectionChanged: _service.isStreaming
                      ? null
                      : (v) => setState(() => _framerate = v.first),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList(ColorScheme cs, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.devices, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Available Devices',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                if (_scanning)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Rescan',
                    onPressed: _startScan,
                  ),
              ],
            ),
            const SizedBox(height: 8),

            if (_scanError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_scanError!,
                    style: TextStyle(color: cs.error, fontSize: 12)),
              ),

            if (_devices != null && _devices!.isEmpty && !_scanning)
              _buildEmptyDevices(cs, theme),

            if (_devices != null)
              ...List.generate(_devices!.length, (i) {
                final device = _devices![i];
                final isCasting = _service.castingTo?.udn == device.udn &&
                    _service.isStreaming;
                return ListTile(
                  leading: Icon(
                    isCasting ? Icons.cast_connected : Icons.tv,
                    color: isCasting ? Colors.green : cs.onSurfaceVariant,
                  ),
                  title: Text(device.name),
                  subtitle: Text(device.address.address,
                      style: TextStyle(fontSize: 12, color: cs.outline)),
                  trailing: isCasting
                      ? Chip(
                          label: const Text('Casting'),
                          backgroundColor:
                              Colors.green.withValues(alpha: 0.15),
                          side: BorderSide.none,
                        )
                      : FilledButton.tonal(
                          onPressed:
                              _service.state != ScreencastState.idle
                                  ? null
                                  : () => _startCast(device),
                          child: const Text('Cast'),
                        ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                );
              }),

            const Divider(height: 24),

            // Manual IP input
            if (_showManualIp) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ipController,
                      decoration: const InputDecoration(
                        hintText: '192.168.1.xxx',
                        labelText: 'Device IP Address',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onSubmitted: (_) => _addManualIp(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _addManualIp,
                    child: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _showManualIp = !_showManualIp),
                icon: Icon(
                    _showManualIp ? Icons.keyboard_arrow_up : Icons.add),
                label: Text(
                    _showManualIp ? 'Hide' : 'Add device by IP'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyDevices(ColorScheme cs, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.tv_off, size: 48, color: cs.outline),
            const SizedBox(height: 8),
            Text('No devices found',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(
              'Make sure your TV is on and connected to the same network.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
            ),
          ],
        ),
      ),
    );
  }
}
