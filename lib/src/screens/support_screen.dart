import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/computation_service.dart';
import '../services/coordinator_service.dart';
import '../services/qubic_service.dart';

/// Full-page screen for the Qubic mining contribution feature.
///
/// Uses gamification, transparency, and clear disclosures to explain
/// that idle CPU cycles mine QUBIC tokens for the developer.
class SupportScreen extends StatefulWidget {
  /// When true the coordinator auto-enables on first build.
  final bool enabled;
  /// Fires when the screen's own start/stop button changes state.
  final ValueChanged<bool>? onEnabledChanged;

  const SupportScreen({
    super.key,
    this.enabled = false,
    this.onEnabledChanged,
  });

  @override
  State<SupportScreen> createState() => SupportScreenState();
}

class SupportScreenState extends State<SupportScreen>
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

  int? _walletBalance;
  bool _balanceLoading = false;

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

    // Honour the initial enabled flag from Settings.
    if (widget.enabled && !_coordinator.enabled) {
      _coordinator.setEnabled(true);
      _compute.setEnabled(true);
    }

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _startBatteryMonitoring();
    _fetchWalletBalance();
  }

  Future<void> _fetchWalletBalance() async {
    _balanceLoading = true;
    if (mounted) setState(() {});
    final balance = await QubicService.fetchBalance();
    _walletBalance = balance;
    _balanceLoading = false;
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant SupportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) {
      _batteryPaused = false;
      _coordinator.setEnabled(widget.enabled);
      _compute.setEnabled(widget.enabled);
    }
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
        debugPrint('SupportScreen: paused compute (battery $_batteryLevel%)');
      }
    } else if (_batteryPaused && (!isOnBattery || !isLow)) {
      if (_coordinator.enabled) {
        _batteryPaused = false;
        _compute.setEnabled(true);
        debugPrint('SupportScreen: resumed compute (power restored)');
      }
    }

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _batteryTimer?.cancel();
    _urlController.dispose();
    _pulseController.dispose();
    // Null callbacks before dispose to avoid setState on defunct widget.
    _compute.onStateChanged = null;
    _coordinator.onStateChanged = null;
    _coordinator.dispose();
    super.dispose();
  }

  int get _totalCompleted => _compute.completedResults.length;

  String get _contributorTier {
    if (_totalCompleted >= 100) return 'Diamond';
    if (_totalCompleted >= 50) return 'Gold';
    if (_totalCompleted >= 20) return 'Silver';
    if (_totalCompleted >= 5) return 'Bronze';
    return 'New Miner';
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
    return Icons.toll;
  }

  int get _nextTierAt {
    if (_totalCompleted >= 100) return _totalCompleted;
    if (_totalCompleted >= 50) return 100;
    if (_totalCompleted >= 20) return 50;
    if (_totalCompleted >= 5) return 20;
    return 5;
  }

  /// Format large hash counts with SI suffixes.
  String _formatHashCount(int n) {
    if (n >= 1000000000) return '${(n / 1000000000).toStringAsFixed(1)}B';
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  /// Rough estimate of current hash rate based on recent completed jobs.
  String _estimateHashRate() {
    final recent = _compute.completedResults
        .where((r) => r.type == ComputeJobType.qubicMining)
        .toList();
    if (recent.isEmpty) return '—';
    // Use the last completed mining job to estimate
    final last = recent.last;
    final iters = last.result['iterations'] as int? ?? 0;
    final ms = last.elapsed.inMilliseconds;
    if (ms <= 0) return '—';
    final rate = (iters / ms * 1000).round();
    return _formatHashCount(rate);
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

        // ── Qubic Wallet ────────────────────────────────────────────
        _buildWalletCard(cs),
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

        // ── FAQ ───────────────────────────────────────────────────────
        if (!isEnabled) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.help_outline, color: cs.primary),
                      const SizedBox(width: 8),
                      const Text('Frequently Asked Questions',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _faqItem(
                    'Will this slow down my device?',
                    'No. Tasks run on idle CPU only and are automatically throttled '
                    'so your downloads, media playback, and other apps are unaffected.',
                  ),
                  _faqItem(
                    'What kind of work does it do?',
                    'Cryptographic computations for the Qubic network: SHA-256 hashing, '
                    'prime factorisation, matrix multiplication, and data integrity checks.',
                  ),
                  _faqItem(
                    'Can I stop at any time?',
                    'Yes — one tap stops all work instantly. No data is stored '
                    'on any server.',
                  ),
                  _faqItem(
                    'Does this mine cryptocurrency?',
                    'Yes — it mines QUBIC tokens using your idle CPU cycles. '
                    'All earnings go to the developer\u2019s wallet to support '
                    'continued development of this app.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Thank you message (when active) ──────────────────────────
        if (isEnabled) ...[
          Card(
            color: cs.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.favorite, color: Colors.red.shade300, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Thank You!',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text(
                          'Every task you complete mines QUBIC tokens for the developer. '
                          'You\u2019re directly supporting continued development of this app!',
                          style: TextStyle(
                              fontSize: 13,
                              color: cs.onPrimaryContainer),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Buy Me a Coffee ──────────────────────────────────────────
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

  Widget _faqItem(String question, String answer) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 4),
          Text(answer,
              style: const TextStyle(fontSize: 13, height: 1.4)),
        ],
      ),
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
                          : Icons.toll_rounded,
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
                            : 'Support the Project',
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
                            : 'Mine QUBIC tokens to support the developer',
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
                'most of the time. With one tap, you can use those '
                'idle cycles to mine QUBIC cryptocurrency. All earnings '
                'go directly to the developer\u2019s wallet.',
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
                        widget.onEnabledChanged?.call(false);
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
                        widget.onEnabledChanged?.call(true);
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
                'SHA-256 hashing, prime factorisation, matrix math, '
                'and data integrity checks — cryptographic workloads '
                'supporting the Qubic network.'),
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
                'Pool URL is visible & editable — full transparency'),
            _guaranteeChip(
                'One tap to stop, instantly — no questions asked'),
            _guaranteeChip(
                'Open source — audit every line of code yourself'),
            _guaranteeChip(
                'Qubic mining — transparent and honest about what it does'),
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
    final isLocal = _coordinator.localMode;
    final isConnected = _coordinator.connected;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              isLocal
                  ? Icons.computer
                  : isConnected
                      ? Icons.cloud_done
                      : Icons.cloud_off,
              color: (isLocal || isConnected) ? Colors.green : cs.error,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_coordinator.connectionStatus,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  if (isLocal)
                    Text(
                      'Tasks are generated on-device. Mining for ${QubicService.walletId.substring(0, 8)}\u2026',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  if (_coordinator.lastError != null && !isLocal)
                    Text(_coordinator.lastError!,
                        style: TextStyle(color: cs.error, fontSize: 12)),
                ],
              ),
            ),
            if (!isConnected && !isLocal && _coordinator.enabled)
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
            const SizedBox(height: 8),
            // ── Mining-specific stats ────────────────────────
            Row(
              children: [
                _statCard(
                    'Solutions',
                    '${_coordinator.solvedCount}',
                    Icons.emoji_events,
                    _coordinator.solvedCount > 0
                        ? Colors.amber
                        : cs.onSurfaceVariant),
                const SizedBox(width: 8),
                _statCard(
                    'Hashes',
                    _formatHashCount(_coordinator.totalHashIterations),
                    Icons.tag,
                    _coordinator.totalHashIterations > 0
                        ? Colors.deepPurple
                        : cs.onSurfaceVariant),
                const SizedBox(width: 8),
                _statCard(
                    'H/s',
                    _compute.activeCount > 0
                        ? _estimateHashRate()
                        : '—',
                    Icons.speed,
                    _compute.activeCount > 0
                        ? Colors.teal
                        : cs.onSurfaceVariant),
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

  Widget _buildWalletCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet, color: cs.primary),
                const SizedBox(width: 8),
                const Text('Qubic Wallet',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_balanceLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Refresh balance',
                    onPressed: _fetchWalletBalance,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Developer\u2019s Wallet Address',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  SelectableText(
                    QubicService.walletId,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: QubicService.walletId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Wallet address copied'),
                          duration: Duration(seconds: 2)),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy Address'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse(QubicService.explorerUrl);
                    if (!await launchUrl(uri,
                        mode: LaunchMode.externalApplication)) {
                      debugPrint('Could not launch $uri');
                    }
                  },
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Explorer'),
                ),
              ],
            ),
            if (_walletBalance != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.toll, size: 18, color: Colors.amber.shade700),
                  const SizedBox(width: 6),
                  Text(
                    'Balance: ${_walletBalance!} QUBIC',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBatteryWarning() {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.battery_alert,
                color: Theme.of(context).colorScheme.onErrorContainer, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Support Paused',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                      'Battery is at $_batteryLevel%. Support will '
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
                const Text('Pool / Coordinator URL:',
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
                          hintText: 'wss://pool.qubic.li',
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
