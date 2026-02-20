import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/download_stats.dart';
import '../services/statistics_service.dart';

/// Dashboard screen showing download statistics with charts.
class StatisticsScreen extends StatefulWidget {
  final StatisticsService statisticsService;

  const StatisticsScreen({super.key, required this.statisticsService});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  void initState() {
    super.initState();
    widget.statisticsService.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  bool get wantKeepAlive => true;

  DownloadStats get _stats => widget.statisticsService.stats;

  bool _isNarrow(BuildContext context) =>
      MediaQuery.of(context).size.width < 600;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final narrow = _isNarrow(context);

    if (_stats.totalDownloads == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart, size: 80, color: cs.outline),
            const SizedBox(height: 16),
            Text('No download data yet',
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text('Statistics will appear here after your first download.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.outline)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Overview cards ──────────────────────────────────────
          _buildOverviewCards(cs, narrow),
          const SizedBox(height: 24),

          // ── Downloads over time ────────────────────────────────
          if (_stats.downloadsByDate.length > 1) ...[
            _sectionHeader(theme, Icons.show_chart, 'Downloads Over Time'),
            const SizedBox(height: 12),
            _buildTimelineChart(cs),
            const SizedBox(height: 24),
          ],

          // ── Format & Source charts side by side on wide ────────
          if (_stats.downloadsByFormat.isNotEmpty ||
              _stats.downloadsBySource.isNotEmpty) ...[
            if (narrow) ...[
              if (_stats.downloadsByFormat.isNotEmpty) ...[
                _sectionHeader(theme, Icons.audio_file, 'Formats'),
                const SizedBox(height: 12),
                _buildFormatChart(cs),
                const SizedBox(height: 24),
              ],
              if (_stats.downloadsBySource.isNotEmpty) ...[
                _sectionHeader(theme, Icons.cloud_download, 'Sources'),
                const SizedBox(height: 12),
                _buildSourceChart(cs),
                const SizedBox(height: 24),
              ],
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_stats.downloadsByFormat.isNotEmpty)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionHeader(theme, Icons.audio_file, 'Formats'),
                          const SizedBox(height: 12),
                          _buildFormatChart(cs),
                        ],
                      ),
                    ),
                  if (_stats.downloadsByFormat.isNotEmpty &&
                      _stats.downloadsBySource.isNotEmpty)
                    const SizedBox(width: 24),
                  if (_stats.downloadsBySource.isNotEmpty)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionHeader(
                              theme, Icons.cloud_download, 'Sources'),
                          const SizedBox(height: 12),
                          _buildSourceChart(cs),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ],

          // ── Top artists ────────────────────────────────────────
          if (_stats.downloadsByArtist.isNotEmpty) ...[
            _sectionHeader(theme, Icons.person, 'Top Artists'),
            const SizedBox(height: 12),
            _buildTopArtists(cs),
            const SizedBox(height: 24),
          ],

          // ── Reset ──────────────────────────────────────────────
          Center(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('Reset Statistics'),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.error,
                side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: _confirmReset,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ─── Section header helper ─────────────────────────────────────────────

  Widget _sectionHeader(ThemeData theme, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ─── Overview cards ────────────────────────────────────────────────────

  Widget _buildOverviewCards(ColorScheme cs, bool narrow) {
    final cards = [
      _OverviewCard(
        icon: Icons.download,
        label: 'Total',
        value: _stats.totalDownloads.toString(),
        color: cs.primary,
        bgColor: cs.primaryContainer,
        fgColor: cs.onPrimaryContainer,
      ),
      _OverviewCard(
        icon: Icons.check_circle,
        label: 'Successful',
        value: _stats.successfulDownloads.toString(),
        color: Colors.green,
        bgColor: Colors.green.withValues(alpha: 0.15),
        fgColor: Colors.green,
      ),
      _OverviewCard(
        icon: Icons.error,
        label: 'Failed',
        value: _stats.failedDownloads.toString(),
        color: cs.error,
        bgColor: cs.errorContainer,
        fgColor: cs.onErrorContainer,
      ),
      _OverviewCard(
        icon: Icons.percent,
        label: 'Success Rate',
        value: '${_stats.successRate.toStringAsFixed(1)}%',
        color: _stats.successRate > 80
            ? Colors.green
            : _stats.successRate > 50
                ? Colors.orange
                : cs.error,
        bgColor: cs.surfaceContainerHighest,
        fgColor: cs.onSurface,
      ),
    ];

    if (narrow) {
      return Column(
        children: [
          Row(children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 8),
            Expanded(child: cards[1]),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: cards[2]),
            const SizedBox(width: 8),
            Expanded(child: cards[3]),
          ]),
        ],
      );
    }

    return Row(
      children: cards
          .expand((c) => [Expanded(child: c), const SizedBox(width: 8)])
          .toList()
        ..removeLast(),
    );
  }

  // ─── Timeline chart ────────────────────────────────────────────────────

  Widget _buildTimelineChart(ColorScheme cs) {
    final sorted = _stats.downloadsByDate.keys.toList()..sort();
    final spots = List.generate(sorted.length,
        (i) => FlSpot(i.toDouble(), _stats.downloadsByDate[sorted[i]]!.toDouble()));

    // Show up to 7 date labels
    final step = (sorted.length / 7).ceil().clamp(1, sorted.length);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
        child: SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 1,
                getDrawingHorizontalLine: (v) => FlLine(
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: step.toDouble(),
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= sorted.length) {
                        return const SizedBox.shrink();
                      }
                      final date = sorted[idx];
                      final short =
                          date.length >= 10 ? date.substring(5) : date;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(short,
                            style: TextStyle(
                                fontSize: 10, color: cs.onSurfaceVariant)),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    getTitlesWidget: (value, meta) {
                      if (value != value.roundToDouble()) {
                        return const SizedBox.shrink();
                      }
                      return Text('${value.toInt()}',
                          style: TextStyle(
                              fontSize: 10, color: cs.onSurfaceVariant));
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots.map((s) {
                    final idx = s.x.toInt();
                    final date =
                        idx >= 0 && idx < sorted.length ? sorted[idx] : '';
                    return LineTooltipItem(
                      '$date\n${s.y.toInt()} downloads',
                      TextStyle(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    );
                  }).toList(),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  preventCurveOverShooting: true,
                  color: cs.primary,
                  barWidth: 3,
                  dotData: FlDotData(
                    show: spots.length <= 14,
                    getDotPainter: (spot, pct, barData, idx) =>
                        FlDotCirclePainter(
                      radius: 3,
                      color: cs.primary,
                      strokeWidth: 0,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: cs.primary.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Format bar chart ──────────────────────────────────────────────────

  Widget _buildFormatChart(ColorScheme cs) {
    final entries = DownloadStats.topEntries(_stats.downloadsByFormat);
    final maxVal =
        entries.fold<int>(0, (m, e) => e.value > m ? e.value : m).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: entries.map((e) {
            final fraction = maxVal > 0 ? e.value / maxVal : 0.0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(e.key.toUpperCase(),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: cs.primary)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 20,
                        backgroundColor:
                            cs.surfaceContainerHighest,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 32,
                    child: Text('${e.value}',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface)),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ─── Source pie chart ─────────────────────────────────────────────────

  Widget _buildSourceChart(ColorScheme cs) {
    final total =
        _stats.downloadsBySource.values.fold(0, (s, v) => s + v);
    const sourceColors = {
      'youtube': Colors.red,
      'soundcloud': Colors.orange,
      'spotify': Colors.green,
    };
    final entries = _stats.downloadsBySource.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              height: 180,
              child: PieChart(
                PieChartData(
                  sections: entries.map((e) {
                    final pct = total > 0 ? (e.value / total) * 100 : 0.0;
                    final color =
                        sourceColors[e.key.toLowerCase()] ?? cs.tertiary;
                    return PieChartSectionData(
                      value: e.value.toDouble(),
                      title: '${pct.toStringAsFixed(0)}%',
                      color: color,
                      radius: 55,
                      titleStyle: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                    );
                  }).toList(),
                  centerSpaceRadius: 32,
                  sectionsSpace: 2,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: entries.map((e) {
                final color =
                    sourceColors[e.key.toLowerCase()] ?? cs.tertiary;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                            color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('${e.key} (${e.value})',
                        style: const TextStyle(fontSize: 12)),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Top artists table ─────────────────────────────────────────────────

  Widget _buildTopArtists(ColorScheme cs) {
    final top = DownloadStats.topEntries(_stats.downloadsByArtist, 10);
    final maxVal =
        top.fold<int>(0, (m, e) => e.value > m ? e.value : m).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: List.generate(top.length, (i) {
            final e = top[i];
            final fraction = maxVal > 0 ? e.value / maxVal : 0.0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text('${i + 1}.',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: cs.onSurfaceVariant,
                            fontSize: 12)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(e.key,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 14,
                        backgroundColor: cs.surfaceContainerHighest,
                        color: i == 0
                            ? Colors.amber
                            : i == 1
                                ? Colors.grey.shade400
                                : i == 2
                                    ? Colors.brown.shade300
                                    : cs.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 28,
                    child: Text('${e.value}',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: cs.onSurface)),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  // ─── Reset confirmation ────────────────────────────────────────────────

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber, color: Theme.of(ctx).colorScheme.error),
        title: const Text('Reset Statistics?'),
        content: const Text(
            'This will permanently delete all download statistics. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.statisticsService.reset();
      if (mounted) setState(() {});
    }
  }
}

// ─── Overview card widget ────────────────────────────────────────────────────

class _OverviewCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color bgColor;
  final Color fgColor;

  const _OverviewCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
    required this.fgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: bgColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: fgColor)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 12, color: fgColor.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }
}
