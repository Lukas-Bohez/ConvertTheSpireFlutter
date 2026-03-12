import 'dart:async';
import 'dart:io' show Platform;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import '../utils/snack.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/computation_service.dart';
import '../services/coordinator_service.dart';
import '../services/native_miner_service.dart';
import '../services/qubic_service.dart';
import '../theme/app_colors.dart';

/// Full-page screen for the Qubic mining contribution feature.
///
/// Uses gamification, transparency, and clear disclosures to explain
/// that idle CPU cycles mine QUBIC tokens for the developer.
class SupportScreen extends StatefulWidget {
  /// When true the coordinator auto-enables on first build.
  final bool enabled;

  /// Fires when the screen's own start/stop button changes state.
  final ValueChanged<bool>? onEnabledChanged;

  /// Externally-managed services that survive tab switches.
  final ComputationService compute;
  final CoordinatorService coordinator;

  const SupportScreen({
    super.key,
    this.enabled = false,
    this.onEnabledChanged,
    required this.compute,
    required this.coordinator,
  });

  @override
  State<SupportScreen> createState() => SupportScreenState();
}

class SupportScreenState extends State<SupportScreen>
    with SingleTickerProviderStateMixin {
  ComputationService get _compute => widget.compute;
  CoordinatorService get _coordinator => widget.coordinator;
  final Battery _battery = Battery();

  int _batteryLevel = 100;
  BatteryState _batteryState = BatteryState.unknown;
  bool _batteryPaused = false;
  Timer? _batteryTimer;
  late final AnimationController _pulseController;
  StreamSubscription? _minerStatsSub;

  int? _walletBalance;
  bool _balanceLoading = false;
  bool _hasShownConsent = false;

  // Mining time tracking
  DateTime? _miningStart;
  int _totalMinedMinutes = 0; // cumulative across sessions
  Timer? _miningTimer;

  @override
  void initState() {
    super.initState();

    // Wire UI refresh callbacks (safe to reassign on each mount).
    _compute.onStateChanged = () {
      if (mounted) setState(() {});
    };
    _coordinator.onStateChanged = () {
      if (mounted) {
        _syncMiningTimer();
        setState(() {});
      }
    };

    // Subscribe to miner stats stream for direct UI updates.
    _minerStatsSub = _coordinator.nativeMiner.statsStream.listen((_) {
      if (mounted) setState(() {});
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _startBatteryMonitoring();
    _fetchWalletBalance();
    _loadMinedMinutes();
    _loadConsentFlag();
    _syncMiningTimer();
    _autoResumeIfNeeded();
  }

  Future<void> _loadConsentFlag() async {
    final prefs = await SharedPreferences.getInstance();
    _hasShownConsent = prefs.getBool('mining_consent_shown') ?? false;
  }

  Future<void> _saveConsentFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mining_consent_shown', true);
    _hasShownConsent = true;
  }

  /// Show a one-time consent dialog before the miner is enabled for the
  /// first time.  Returns `true` if the user accepted.
  Future<bool> _showConsentDialog() async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Opt-in Mining'),
        content: const Text(
          'This feature uses your idle CPU cycles to mine QUBIC '
          'cryptocurrency. All earnings go to the developer\u2019s '
          'wallet to support continued development of this free app.\n\n'
          'Mining runs at below-normal priority and pauses automatically '
          'when your battery is low. You can stop at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('I Understand — Start'),
          ),
        ],
      ),
    );
    return accepted ?? false;
  }

  /// Called when the user taps "Start Contributing".  Shows the consent
  /// dialog on first use, then enables mining.
  Future<void> _onStartContributing() async {
    if (!_hasShownConsent) {
      final accepted = await _showConsentDialog();
      if (!accepted) return;
      await _saveConsentFlag();
    }
    _batteryPaused = false;
    _coordinator.setEnabled(true);
    _compute.setEnabled(true);
    widget.onEnabledChanged?.call(true);
  }

  /// Auto-resume mining if it was enabled in a previous session.
  Future<void> _autoResumeIfNeeded() async {
    if (kIsWeb || (!kIsWeb && Platform.isAndroid)) return;
    if (_coordinator.enabled) return; // already running
    final wasEnabled = await _coordinator.restoreEnabledState();
    if (wasEnabled && mounted) {
      _coordinator.setEnabled(true);
      _compute.setEnabled(true);
      widget.onEnabledChanged?.call(true);
    }
  }

  Future<void> _fetchWalletBalance() async {
    _balanceLoading = true;
    if (mounted) setState(() {});
    final balance = await QubicService.fetchBalance();
    _walletBalance = balance;
    _balanceLoading = false;
    if (mounted) setState(() {});
  }

  Future<void> _loadMinedMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    _totalMinedMinutes = prefs.getInt('mining_total_minutes') ?? 0;
    if (mounted) setState(() {});
  }

  Future<void> _saveMinedMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('mining_total_minutes', _totalMinedMinutes);
  }

  /// Start or stop the per-minute mining timer based on mining state.
  void _syncMiningTimer() {
    final isMining = _coordinator.enabled &&
        (_coordinator.connected || _coordinator.nativeMiner.isRunning);
    if (isMining && _miningStart == null) {
      _miningStart = DateTime.now();
      _miningTimer ??= Timer.periodic(const Duration(minutes: 1), (_) {
        if (_miningStart != null) {
          _totalMinedMinutes++;
          _saveMinedMinutes();
          if (mounted) setState(() {});
        }
      });
    } else if (!isMining && _miningStart != null) {
      _miningStart = null;
      _miningTimer?.cancel();
      _miningTimer = null;
    }
  }

  @override
  void didUpdateWidget(covariant SupportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) {
      final _isAndroid = !kIsWeb && Platform.isAndroid;
      if (_isAndroid) return; // never enable on Android
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
      if (kDebugMode) debugPrint('Battery check failed: $e');
      _batteryLevel = 100;
      _batteryState = BatteryState.full;
    }

    final isOnBattery = _batteryState == BatteryState.discharging;
    final isLow = _batteryLevel < 30;

    if (_coordinator.enabled && isOnBattery && isLow) {
      if (!_batteryPaused) {
        _batteryPaused = true;
        _compute.setEnabled(false);
        // Also pause the native miner subprocess.
        _coordinator.nativeMiner.stop();
        if (kDebugMode)
          debugPrint(
              'SupportScreen: paused compute + miner (battery $_batteryLevel%)');
      }
    } else if (_batteryPaused && (!isOnBattery || !isLow)) {
      if (_coordinator.enabled) {
        _batteryPaused = false;
        _compute.setEnabled(true);
        // Resume native miner if on a supported platform.
        if (_coordinator.nativeMinerSupported) {
          _coordinator.restartNativeMiner();
        }
        if (kDebugMode)
          debugPrint('SupportScreen: resumed compute + miner (power restored)');
      }
    }

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _batteryTimer?.cancel();
    _miningTimer?.cancel();
    _minerStatsSub?.cancel();
    _pulseController.dispose();
    // Null callbacks to avoid setState on defunct widget.
    // Services are NOT disposed here — they are owned by HomeScreenState.
    _compute.onStateChanged = null;
    _coordinator.onStateChanged = null;
    super.dispose();
  }

  int get _totalCompleted => _compute.completedResults.length;

  double get _totalMinedHours => _totalMinedMinutes / 60.0;

  String get _minedTimeLabel {
    final h = _totalMinedMinutes ~/ 60;
    final m = _totalMinedMinutes % 60;
    if (h > 0) return '$h h $m min mined';
    return '$m min mined';
  }

  String get _contributorTier {
    if (_totalMinedHours >= 100) return 'Diamond';
    if (_totalMinedHours >= 24) return 'Gold';
    if (_totalMinedHours >= 5) return 'Silver';
    if (_totalMinedHours >= 1) return 'Bronze';
    return 'New Miner';
  }

  Color _tierColor(BuildContext context) {
    if (_totalMinedHours >= 100) return Colors.cyanAccent;
    if (_totalMinedHours >= 24) return Colors.amber;
    if (_totalMinedHours >= 5) return Colors.grey.shade400;
    if (_totalMinedHours >= 1) return Colors.brown.shade300;
    return Theme.of(context).colorScheme.primary;
  }

  IconData get _tierIcon {
    if (_totalMinedHours >= 100) return Icons.diamond;
    if (_totalMinedHours >= 24) return Icons.workspace_premium;
    if (_totalMinedHours >= 5) return Icons.military_tech;
    if (_totalMinedHours >= 1) return Icons.star;
    return Icons.toll;
  }

  /// Next tier threshold in minutes.
  int get _nextTierMinutes {
    if (_totalMinedMinutes >= 6000) return _totalMinedMinutes; // Diamond (100h)
    if (_totalMinedMinutes >= 1440) return 6000; // → Diamond
    if (_totalMinedMinutes >= 300) return 1440; // → Gold (24h)
    if (_totalMinedMinutes >= 60) return 300; // → Silver (5h)
    return 60; // → Bronze (1h)
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

  // ── Support level helpers (1-10 scale ↔ CPU threads) ───────────

  int get _maxThreads => !kIsWeb && !_isWeb() ? Platform.numberOfProcessors : 4;

  int _levelForThreads(int threads) {
    if (_maxThreads <= 1) return 1;
    return ((threads / _maxThreads) * 10).round().clamp(1, 10);
  }

  int _threadsForLevel(int level) {
    return ((level / 10) * _maxThreads).ceil().clamp(1, _maxThreads);
  }

  String _levelLabel(int level) {
    if (level <= 2) return 'Minimal';
    if (level <= 4) return 'Light';
    if (level <= 6) return 'Medium';
    if (level <= 8) return 'High';
    return 'Maximum';
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
          _buildHowItWorksCard(cs),
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
                    'On desktop (Windows/Linux) it runs the official qli-Client to perform '
                        'AI training computations for the Qubic network (pool mining via qubic.li). '
                        'On other platforms it runs simulated cryptographic tasks locally.',
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
                              fontSize: 13, color: cs.onPrimaryContainer),
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
            subtitle: const Text('Help keep this project free & open-source'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () async {
              final uri = Uri.parse('https://buymeacoffee.com/orokaconner');
              if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
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
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 4),
          Text(answer, style: const TextStyle(fontSize: 13, height: 1.4)),
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
            ? BorderSide(
                color: context.success.withValues(alpha: 0.7), width: 2)
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
                    scale:
                        isEnabled ? 1.0 + (_pulseController.value * 0.1) : 1.0,
                    child: child,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isEnabled
                          ? context.success.withValues(alpha: 0.12)
                          : cs.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isEnabled ? Icons.flash_on_rounded : Icons.toll_rounded,
                      size: 28,
                      color: isEnabled ? context.success : cs.primary,
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
                              ? context.success.withValues(alpha: 0.85)
                              : cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isEnabled
                            ? _minedTimeLabel
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
              child: (!kIsWeb && Platform.isAndroid)
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 16),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.info_outline, color: cs.onSurfaceVariant),
                          const SizedBox(height: 8),
                          Text(
                            'Not available on Android',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Support us on Windows and Linux instead!',
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : isEnabled
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
                          onPressed: _onStartContributing,
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
            _whyRow(
                Icons.security,
                'Real Mining',
                'On desktop, your CPU runs official Qubic pool mining via '
                    'qli-Client. Solutions earn real QUBIC tokens paid to the '
                    'developer\u2019s wallet.'),
            _whyRow(
                Icons.shield_outlined,
                '100% Safe',
                'Runs in sandboxed Dart Isolates — no access to your files, '
                    'network, or personal data. Zero risk.'),
            _whyRow(
                Icons.battery_charging_full,
                'Battery Smart',
                'Automatically pauses when battery drops below 30%. '
                    'Resumes when plugged in.'),
            _whyRow(
                Icons.speed,
                'Zero Impact',
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
          Icon(icon, size: 20, color: context.success),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.school_outlined, color: cs.primary),
                const SizedBox(width: 8),
                const Text('How Qubic Mining Works',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 14),
            _howStep(
              '1',
              'Weekly Epochs',
              'Qubic operates on a weekly cycle called an epoch. '
                  'Each epoch runs from Wednesday to Wednesday and is made '
                  'up of many short rounds (roughly ~7-second intervals). '
                  'During each round your CPU solves AI training tasks.',
            ),
            _howStep(
              '2',
              'Mining in Rounds',
              'In every round, the qli-Client sends your CPU a small '
                  'AI training workload. Your processor solves it and submits '
                  'the answer back to the Qubic network. The faster your CPU, '
                  'the more solutions you contribute per epoch.',
            ),
            _howStep(
              '3',
              'Earning QUBIC Tokens',
              'At the end of each epoch the Qubic network distributes newly '
                  'created QUBIC tokens. Miners are ranked by the number of valid '
                  'solutions they submitted. More solutions = larger share of the '
                  'weekly token distribution.',
            ),
            _howStep(
              '4',
              'Pool Mining',
              'This app connects to a mining pool (qubic.li) which combines '
                  'your hashpower with other miners. Rewards are split '
                  'proportionally based on your contribution, so even modest '
                  'hardware earns a steady share every week.',
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: cs.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'All QUBIC earnings go to the developer\u2019s wallet '
                      'to fund continued development of this free app. '
                      'You\u2019re supporting the project just by leaving '
                      'mining on!',
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onPrimaryContainer,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _howStep(String number, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _tierColor(context).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(number,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                )),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(fontSize: 13, height: 1.4)),
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
                Icon(Icons.verified_user,
                    color: context.success.withValues(alpha: 0.8)),
                const SizedBox(width: 8),
                const Text('Our Guarantees',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            _guaranteeChip('Opt-in only — never runs without your consent'),
            _guaranteeChip(
                'Uses official qli-Client from qubic.li — transparent & auditable'),
            _guaranteeChip('One tap to stop, instantly — no questions asked'),
            _guaranteeChip('Open source — audit every line of code yourself'),
            _guaranteeChip(
                'Real Qubic pool mining — earnings visible on chain'),
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
          Icon(Icons.check_circle,
              size: 18, color: context.success.withValues(alpha: 0.8)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildTierCard(ColorScheme cs) {
    final nextMin = _nextTierMinutes;
    final progress = nextMin > 0 ? _totalMinedMinutes / nextMin : 1.0;
    final remaining = nextMin - _totalMinedMinutes;
    final remainLabel = remaining > 60
        ? '${(remaining / 60).ceil()} h to next tier'
        : '$remaining min to next tier';
    final atMax = _totalMinedMinutes >= 6000;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _tierColor(context).withValues(alpha: 0.5)),
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
                    Text(_minedTimeLabel,
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
                const Spacer(),
                if (!atMax)
                  Text(remainLabel,
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
            if (!atMax) ...[
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
    final miner = _coordinator.nativeMiner;
    final isNative = _coordinator.nativeMinerSupported;
    final isRunning = isNative && miner.isRunning;
    final isMinerStarting = isNative && miner.state == MinerState.starting;
    final isActuallyMining = isRunning &&
        (miner.hashRate > 0 || miner.avgHashRate > 0 || miner.epoch > 0);
    final isLocal = _coordinator.localMode;
    final isConnected = _coordinator.connected;
    final isStarting = isMinerStarting || (isRunning && !isActuallyMining);

    // Downloading / extracting progress
    if (isNative &&
        (miner.state == MinerState.downloading ||
            miner.state == MinerState.extracting ||
            miner.state == MinerState.starting)) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Text(miner.statusMessage,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                ],
              ),
              if (miner.state == MinerState.downloading) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: miner.downloadProgress,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 4),
                Text('${(miner.downloadProgress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 12, color: cs.outline)),
              ],
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (isStarting)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                isActuallyMining
                    ? Icons.cloud_done
                    : isLocal
                        ? Icons.computer
                        : isConnected
                            ? Icons.cloud_done
                            : Icons.cloud_off,
                color: (isActuallyMining || isLocal || isConnected)
                    ? Colors.green
                    : cs.error,
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_coordinator.connectionStatus,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  if (isActuallyMining)
                    Text(
                      'Pool mining via qli-Client \u2022 Payout to ${QubicService.walletId.substring(0, 8)}\u2026',
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    )
                  else if (isStarting)
                    Text(
                      'Connecting to mining pool\u2026',
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    )
                  else if (isLocal)
                    Text(
                      'Simulated tasks on-device (desktop required for real mining)',
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  if (_coordinator.lastError != null &&
                      _coordinator.lastError!.isNotEmpty &&
                      !isRunning &&
                      !isStarting &&
                      !isLocal)
                    Text(_coordinator.lastError!,
                        style: TextStyle(color: cs.error, fontSize: 12)),
                  if (isNative && miner.state == MinerState.error)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await miner.manualRetry();
                          if (mounted) setState(() {});
                        },
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboard(ColorScheme cs) {
    final miner = _coordinator.nativeMiner;
    // Show native dashboard whenever native mining is supported and we're not
    // in local-fallback mode (covers starting, running, error states).
    final isNative =
        _coordinator.nativeMinerSupported && !_coordinator.localMode;

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
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (isNative)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: context.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('POOL',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.green)),
                  )
                else if (_coordinator.localMode)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.outline.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('LOCAL',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: cs.outline)),
                  ),
              ],
            ),
            const Divider(),

            // ── Mining stats row ─────────────────────────────────────
            if (isNative) ...[
              // Native miner stats from qli-Client
              Row(
                children: [
                  _statCard(
                      'Speed',
                      miner.hashRate > 0
                          ? _formatHashCount(miner.hashRate.round())
                          : '\u2014',
                      Icons.speed,
                      miner.hashRate > 0 ? Colors.teal : cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  _statCard(
                      'Avg Speed',
                      miner.avgHashRate > 0
                          ? _formatHashCount(miner.avgHashRate.round())
                          : '\u2014',
                      Icons.trending_up,
                      miner.avgHashRate > 0
                          ? Colors.blue
                          : cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  _statCard(
                      'Round',
                      miner.epoch > 0 ? '${miner.epoch}' : '\u2014',
                      Icons.calendar_today,
                      miner.epoch > 0
                          ? Colors.deepPurple
                          : cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  _statCard(
                      'Solutions',
                      '${miner.solutionsFound}',
                      Icons.emoji_events,
                      miner.solutionsFound > 0
                          ? Colors.amber
                          : cs.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _statCard(
                      'Battery',
                      '$_batteryLevel%',
                      _batteryLevel > 50
                          ? Icons.battery_full
                          : Icons.battery_3_bar,
                      _batteryLevel > 30 ? context.success : context.warning),
                  const SizedBox(width: 8),
                  _statCard(
                      'Support',
                      '${_levelForThreads(miner.cpuThreads)}/10',
                      Icons.favorite,
                      cs.primary),
                ],
              ),
              const SizedBox(height: 12),
              // Link to pool dashboard
              InkWell(
                onTap: () async {
                  final uri = Uri.parse(
                      '${QubicService.poolDashboardUrl}/en-US/mining/overview?payoutId=${QubicService.walletId}');
                  if (!await launchUrl(uri,
                      mode: LaunchMode.externalApplication)) {
                    debugPrint('Could not launch $uri');
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.open_in_new, size: 14, color: cs.primary),
                      const SizedBox(width: 6),
                      Text('View pool stats on qubic.li',
                          style: TextStyle(fontSize: 12, color: cs.primary)),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // Local simulated mode stats
              Row(
                children: [
                  _statCard(
                      'Active',
                      '${_compute.activeCount}',
                      Icons.memory,
                      _compute.activeCount > 0
                          ? context.success
                          : cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  _statCard('Queued', '${_compute.queuedCount}',
                      Icons.hourglass_top, cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  _statCard('Done', '$_totalCompleted', Icons.check_circle,
                      _totalCompleted > 0 ? Colors.blue : cs.onSurfaceVariant),
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
                      _compute.activeCount > 0 ? _estimateHashRate() : '\u2014',
                      Icons.speed,
                      _compute.activeCount > 0
                          ? Colors.teal
                          : cs.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 12),
              if (_compute.runningJobIds.isNotEmpty) ...[
                const Text('Running:',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                for (final r in _compute.completedResults.reversed.take(5))
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 3),
                    child: Row(
                      children: [
                        const Icon(Icons.check, size: 14, color: Colors.green),
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
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
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
                    fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: color.withValues(alpha: 0.7))),
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
                    Snack.show(context, 'Wallet address copied',
                        level: SnackLevel.success,
                        duration: const Duration(seconds: 2));
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
                color: Theme.of(context).colorScheme.onErrorContainer,
                size: 24),
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
    final miner = _coordinator.nativeMiner;
    final isNative = _coordinator.nativeMinerSupported;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          backgroundColor: Theme.of(context).cardColor,
          collapsedBackgroundColor: Theme.of(context).cardColor,
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Icon(Icons.settings, color: cs.primary),
          title: const Text('Advanced Settings'),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Mining mode info ──────────────────────────────
                  if (isNative) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle,
                              color: Colors.green, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Real pool mining via qli-Client v${NativeMinerService.clientVersion}\n'
                              'Registerless mode \u2022 PPS (Pay Per Share)',
                              style:
                                  TextStyle(fontSize: 12, color: cs.onSurface),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.errorContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: cs.error, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Real Qubic mining requires Windows or Linux.\n'
                              'Running simulated tasks on this platform.',
                              style: TextStyle(
                                  fontSize: 12, color: cs.onErrorContainer),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Support level slider (1-10) ──────────────────
                  if (isNative) ...[
                    Text(
                      'How much would you like to support?',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Level ${_levelForThreads(miner.cpuThreads)} \u2014 ${_levelLabel(_levelForThreads(miner.cpuThreads))}',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: cs.primary),
                          ),
                        ),
                        Text(
                          'Using ${miner.cpuThreads} of $_maxThreads cores',
                          style: TextStyle(fontSize: 11, color: cs.outline),
                        ),
                      ],
                    ),
                    Slider(
                      value: _levelForThreads(miner.cpuThreads).toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: '${_levelForThreads(miner.cpuThreads)}',
                      onChanged: (val) {
                        final threads = _threadsForLevel(val.round());
                        miner.setCpuThreads(threads);
                        setState(() {});
                      },
                    ),
                    Text(
                      'Higher = more support, uses more of your computer\u2019s power.\n'
                      '1 = barely noticeable, 10 = full power.',
                      style: TextStyle(fontSize: 11, color: cs.outline),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Text('Parallel workers: ${_compute.maxConcurrent}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500)),
                        const Spacer(),
                        Text('(1 = minimal, 4 = max throughput)',
                            style: TextStyle(fontSize: 11, color: cs.outline)),
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
                  ],

                  // ── Restart miner button (native only) ────────────
                  if (isNative && miner.isRunning) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await _coordinator.restartNativeMiner();
                          if (mounted) setState(() {});
                        },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Apply changes'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

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
                  if (isNative) ...[
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () async {
                        final uri = Uri.parse(
                            '${QubicService.poolDashboardUrl}/en-US/setup');
                        if (!await launchUrl(uri,
                            mode: LaunchMode.externalApplication)) {
                          debugPrint('Could not launch $uri');
                        }
                      },
                      child: Text(
                        'Pool setup guide: pool.qubic.li',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Helper to avoid importing dart:io on web.
  static bool _isWeb() => kIsWeb;
}
