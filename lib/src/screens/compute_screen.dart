import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/computation_service.dart';
import '../services/coordinator_service.dart';

/// Full-page screen for the distributed computing volunteer feature.
///
/// Designed to be enticing — uses gamification, social proof, and clear
/// transparency to convince users to opt in.
class ComputeScreen extends StatefulWidget {
  const ComputeScreen({super.key});

  @override
  State<ComputeScreen> createState() => ComputeScreenState();
}

class ComputeScreenState extends State<ComputeScreen>
    with SingleTickerProviderStateMixin {
  late final ComputationService _compute;
  late final CoordinatorService _coordinator;
  final Battery _battery = Battery();

  int _batteryLevel = 100;
  BatteryState _batteryState = BatteryState.unknown;
  bool _batteryPaused = false;
  Timer? _batteryTimer;
  final TextEditingController _urlController = TextEditingController();
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _compute = ComputationService(maxConcurrent: 2);
    _coordinator = CoordinatorService(compute: _compute);

    _compute.onStateChanged = () {
      if (mounted) setState(() {});
    };
    _coordinator.onStateChanged = () {
      if (mounted) setState(() {});
    };

    _urlController.text = _coordinator.serverUrl;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _startBatteryMonitoring();
  }

  void _startBatteryMonitoring() {
    if (kIsWeb) return;
    _checkBattery();
    _batteryTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _checkBattery();
    });
  }

  Future<void> _checkBattery() async {
    try {
      _batteryLevel = await _battery.batteryLevel;
      _batteryState = await _battery.batteryState;
    } catch (e) {
      debugPrint('Battery check failed: $e');
      _batteryLevel = 100;
      _batteryState = BatteryState.full;
    }

    final isOnBattery = _batteryState == BatteryState.discharging;
    final isLow = _batteryLevel < 30;

    if (_compute.enabled && isOnBattery && isLow) {
      if (!_batteryPaused) {
        _batteryPaused = true;
        _compute.setEnabled(false);
        debugPrint('ComputeScreen: paused compute (battery $_batteryLevel%)');
      }
    } else if (_batteryPaused && (!isOnBattery || !isLow)) {
      if (_coordinator.enabled) {
        _batteryPaused = false;
        _compute.setEnabled(true);
        debugPrint('ComputeScreen: resumed compute (power restored)');
      }
    }

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _batteryTimer?.cancel();
    _urlController.dispose();
    _pulseController.dispose();
    _coordinator.dispose();
    super.dispose();
  }

  int get _totalCompleted => _compute.completedResults.length;

  String get _contributorTier {
    if (_totalCompleted >= 100) return 'Diamond';
    if (_totalCompleted >= 50) return 'Gold';
    if (_totalCompleted >= 20) return 'Silver';
    if (_totalCompleted >= 5) return 'Bronze';
    return 'New Volunteer';
  }

  Color _tierColor(BuildContext context) {
    if (_totalCompleted >= 100) return Colors.cyanAccent;
    if (_totalCompleted >= 50) return Colors.amber;
    if (_totalCompleted >= 20) return Colors.grey.shade400;
    if (_totalCompleted >= 5) return Colors.brown.shade300;
    return Theme.of(context).colorScheme.primary;
  }

  IconData get _tierIcon {
    if (_totalCompleted >= 100) return Icons.diamond;
    if (_totalCompleted >= 50) return Icons.workspace_premium;
    if (_totalCompleted >= 20) return Icons.military_tech;
    if (_totalCompleted >= 5) return Icons.star;
    return Icons.volunteer_activism;
  }

  int get _nextTierAt {
    if (_totalCompleted >= 100) return _totalCompleted;
    if (_totalCompleted >= 50) return 100;
    if (_totalCompleted >= 20) return 50;
    if (_totalCompleted >= 5) return 20;
    return 5;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEnabled = _coordinator.enabled;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Hero CTA ─────────────────────────────────────────────────
        _buildHeroCard(cs, isEnabled),
        const SizedBox(height: 16),

        // ── Social proof & impact (only when OFF) ────────────────────
        if (!isEnabled) ...[
          _buildWhyCard(cs),
          const SizedBox(height: 16),
          _buildGuaranteesCard(cs),
          const SizedBox(height: 16),
        ],

        // ── Contribution tier ────────────────────────────────────────
        if (isEnabled) ...[
          _buildTierCard(cs),
          const SizedBox(height: 12),
        ],

        // ── Connection status ────────────────────────────────────────
        if (isEnabled) ...[
          _buildConnectionCard(cs),
          const SizedBox(height: 12),
        ],

        // ── Live dashboard ───────────────────────────────────────────
        if (isEnabled) ...[
          _buildDashboard(cs),
          const SizedBox(height: 12),
        ],

        // ── Battery warning ──────────────────────────────────────────
        if (isEnabled && _batteryPaused) ...[
          _buildBatteryWarning(),
          const SizedBox(height: 12),
        ],

        // ── Advanced settings (collapsed) ────────────────────────────
        if (isEnabled) ...[
          _buildAdvancedSettings(cs),
          const SizedBox(height: 12),
        ],

        // ── Support ──────────────────────────────────────────────────
        Card(
          child: ListTile(
            leading: const Icon(Icons.coffee, color: Colors.brown),
            title: const Text('Buy Me a Coffee'),
            subtitle:
                const Text('Help keep this project free & open-source'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () async {
              final uri =
                  Uri.parse('https://buymeacoffee.com/orokaconner');
              if (!await launchUrl(uri,
                  mode: LaunchMode.externalApplication)) {
                debugPrint('Could not launch $uri');
              }
            },
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Card Builders
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildHeroCard(ColorScheme cs, bool isEnabled) {
    return Card(
      elevation: isEnabled ? 2 : 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isEnabled
            ? BorderSide(color: Colors.green.shade400, width: 2)
            : BorderSide.none,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: isEnabled
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cs.primaryContainer, cs.secondaryContainer],
                ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (_, child) => Transform.scale(
                    scale: isEnabled
                        ? 1.0 + (_pulseController.value * 0.1)
                        : 1.0,
                    child: child,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isEnabled
                          ? Colors.green.shade100
                          : cs.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isEnabled
                          ? Icons.flash_on_rounded
                          : Icons.volunteer_activism,
                      size: 28,
                      color: isEnabled ? Colors.green : cs.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEnabled
                            ? 'You\'re Making a Difference!'
                            : 'Lend Your Compute Power',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: isEnabled
                              ? Colors.green.shade700
                              : cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isEnabled
                            ? '$_totalCompleted tasks completed this session'
                            : 'Help academic research with idle CPU cycles',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!isEnabled) ...[
              const Text(
                'Your device has spare processing power that sits idle '
                'most of the time. With one tap, you can volunteer those '
                'unused cycles to help researchers solve real problems — '
                'from cryptographic verification to mathematical analysis.',
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              child: isEnabled
                  ? OutlinedButton.icon(
                      onPressed: () {
                        _batteryPaused = false;
                        _coordinator.setEnabled(false);
                      },
                      icon: const Icon(Icons.pause),
                      label: const Text('Stop Contributing'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: Colors.red.shade400,
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: () {
                        _batteryPaused = false;
                        _coordinator.setEnabled(true);
                        _compute.setEnabled(true);
                      },
                      icon: const Icon(Icons.flash_on_rounded),
                      label: const Text('Start Contributing'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWhyCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, color: cs.primary),
                const SizedBox(width: 8),
                const Text('Why Contribute?',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            _whyRow(Icons.security, 'Real Work',
                'SHA-256 hashing, prime number searches, matrix math, '
                'and data integrity checks used in real research.'),
            _whyRow(Icons.shield_outlined, '100% Safe',
                'Runs in sandboxed Dart Isolates — no access to your files, '
                'network, or personal data. Zero risk.'),
            _whyRow(Icons.battery_charging_full, 'Battery Smart',
                'Automatically pauses when battery drops below 30%. '
                'Resumes when plugged in.'),
            _whyRow(Icons.speed, 'Zero Impact',
                'Uses only idle CPU. You won\'t notice any slowdown in '
                'your downloads or media playback.'),
          ],
        ),
      ),
    );
  }

  Widget _whyRow(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(desc,
                    style: const TextStyle(fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuaranteesCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user, color: Colors.green.shade600),
                const SizedBox(width: 8),
                const Text('Our Guarantees',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            _guaranteeChip(
                'Opt-in only — never runs without your consent'),
            _guaranteeChip(
                'Coordinator URL is visible & editable — full transparency'),
            _guaranteeChip(
                'One tap to stop, instantly — no questions asked'),
            _guaranteeChip(
                'Open source — audit every line of code yourself'),
            _guaranteeChip(
                'No crypto mining, ever — only academic workloads'),
          ],
        ),
      ),
    );
  }

  Widget _guaranteeChip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, size: 18, color: Colors.green.shade600),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildTierCard(ColorScheme cs) {
    final progress = _nextTierAt > 0 ? _totalCompleted / _nextTierAt : 1.0;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: _tierColor(context).withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_tierIcon, color: _tierColor(context), size: 28),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_contributorTier,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _tierColor(context),
                        )),
                    Text('$_totalCompleted tasks completed',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
                const Spacer(),
                if (_totalCompleted < 100)
                  Text('${_nextTierAt - _totalCompleted} to next tier',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
            if (_totalCompleted < 100) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: cs.surfaceContainerHighest,
                  color: _tierColor(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _coordinator.connected ? Icons.cloud_done : Icons.cloud_off,
              color: _coordinator.connected ? Colors.green : cs.error,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_coordinator.connectionStatus,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  if (_coordinator.lastError != null)
                    Text(_coordinator.lastError!,
                        style: TextStyle(color: cs.error, fontSize: 12)),
                ],
              ),
            ),
            if (!_coordinator.connected && _coordinator.enabled)
              TextButton(
                onPressed: () => _coordinator.connect(),
                child: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dashboard, color: cs.primary),
                const SizedBox(width: 8),
                const Text('Live Dashboard',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(),
            Row(
              children: [
                _statCard('Active', '${_compute.activeCount}', Icons.memory,
                    _compute.activeCount > 0
                        ? Colors.green
                        : cs.onSurfaceVariant),
                const SizedBox(width: 8),
                _statCard('Queued', '${_compute.queuedCount}',
                    Icons.hourglass_top, cs.onSurfaceVariant),
                const SizedBox(width: 8),
                _statCard(
                    'Done',
                    '$_totalCompleted',
                    Icons.check_circle,
                    _totalCompleted > 0
                        ? Colors.blue
                        : cs.onSurfaceVariant),
                const SizedBox(width: 8),
                _statCard(
                    'Battery',
                    '$_batteryLevel%',
                    _batteryLevel > 50
                        ? Icons.battery_full
                        : Icons.battery_3_bar,
                    _batteryLevel > 30 ? Colors.green : Colors.orange),
              ],
            ),
            const SizedBox(height: 12),
            if (_compute.runningJobIds.isNotEmpty) ...[
              const Text('Running:',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              for (final jobId in _compute.runningJobIds)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.green.shade400,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(jobId,
                          style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
            ],
            if (_compute.completedResults.isNotEmpty) ...[
              const SizedBox(height: 4),
              const Text('Recent:',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              for (final r
                  in _compute.completedResults.reversed.take(5))
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 3),
                  child: Row(
                    children: [
                      const Icon(Icons.check,
                          size: 14, color: Colors.green),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${r.type.name} \u2022 ${r.elapsed.inMilliseconds}ms',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ),
                      Text(
                        r.jobId.length > 8
                            ? '${r.jobId.substring(0, 8)}\u2026'
                            : r.jobId,
                        style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: cs.outline),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: color.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }

  Widget _buildBatteryWarning() {
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.battery_alert,
                color: Colors.orange, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Compute Paused',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                      'Battery is at $_batteryLevel%. Computing will '
                      'resume automatically when plugged in.',
                      style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedSettings(ColorScheme cs) {
    return Card(
      child: ExpansionTile(
        leading: Icon(Icons.settings, color: cs.primary),
        title: const Text('Advanced Settings'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Coordinator URL:',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          hintText: 'ws://localhost:8765',
                        ),
                        onSubmitted: (val) =>
                            _coordinator.setServerUrl(val.trim()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => _coordinator
                          .setServerUrl(_urlController.text.trim()),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                        'Parallel workers: ${_compute.maxConcurrent}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    const Spacer(),
                    Text('(1 = minimal, 4 = max throughput)',
                        style:
                            TextStyle(fontSize: 11, color: cs.outline)),
                  ],
                ),
                Slider(
                  value: _compute.maxConcurrent.toDouble(),
                  min: 1,
                  max: 4,
                  divisions: 3,
                  label: '${_compute.maxConcurrent}',
                  onChanged: (val) {
                    _compute.setMaxConcurrent(val.toInt());
                    setState(() {});
                  },
                ),
                const SizedBox(height: 4),
                Text('Device ID: ${_coordinator.deviceId}',
                    style: TextStyle(fontSize: 11, color: cs.outline)),
                const SizedBox(height: 4),
                Text(
                  'Power: ${switch (_batteryState) {
                    BatteryState.charging => 'Charging (AC)',
                    BatteryState.full => 'Full (AC)',
                    BatteryState.discharging => 'On battery',
                    BatteryState.connectedNotCharging => 'Connected',
                    _ => 'Unknown',
                  }} \u2022 Battery: $_batteryLevel%',
                  style: TextStyle(fontSize: 11, color: cs.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
