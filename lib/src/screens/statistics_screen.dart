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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            // ── Overview cards ──────────────────────────────────────
            Row(
              children: [
                Expanded(child: _StatCard('Total', _stats.totalDownloads.toString())),
                const SizedBox(width: 8),
                Expanded(child: _StatCard('Success', '${_stats.successRate.toStringAsFixed(1)}%')),
                const SizedBox(width: 8),
                Expanded(child: _StatCard('Failed', _stats.failedDownloads.toString())),
              ],
            ),
            const SizedBox(height: 24),

            // ── Downloads over time ────────────────────────────────
            if (_stats.downloadsByDate.isNotEmpty) ...[
              Text('Downloads Over Time', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: LineChart(
                  LineChartData(
                    gridData: const FlGridData(show: true),
                    titlesData: const FlTitlesData(
                      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: _dateSpots(_stats.downloadsByDate),
                        isCurved: true,
                        color: Colors.teal,
                        barWidth: 3,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(show: true, color: Colors.teal.withValues(alpha: 0.15)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // ── Top artists ────────────────────────────────────────
            if (_stats.downloadsByArtist.isNotEmpty) ...[
              Text('Top Artists', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              ...DownloadStats.topEntries(_stats.downloadsByArtist, 10).map(
                (e) => ListTile(
                  dense: true,
                  title: Text(e.key),
                  trailing: Text('${e.value}'),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // ── Source breakdown ────────────────────────────────────
            if (_stats.downloadsBySource.isNotEmpty) ...[
              Text('Download Sources', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: PieChart(
                  PieChartData(
                    sections: _sourceSections(_stats.downloadsBySource),
                    centerSpaceRadius: 40,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // ── Format breakdown ───────────────────────────────────
            if (_stats.downloadsByFormat.isNotEmpty) ...[
              Text('Formats', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              ...DownloadStats.topEntries(_stats.downloadsByFormat).map(
                (e) => ListTile(
                  dense: true,
                  title: Text(e.key.toUpperCase()),
                  trailing: Text('${e.value}'),
                ),
              ),
            ],

            const SizedBox(height: 24),
            Center(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('Reset Statistics'),
                onPressed: () async {
                  await widget.statisticsService.reset();
                  if (mounted) setState(() {});
                },
              ),
            ),
          ],
        ),
    );
  }

  // ─── Chart helpers ─────────────────────────────────────────────────────

  List<FlSpot> _dateSpots(Map<String, int> dateMap) {
    final sorted = dateMap.keys.toList()..sort();
    return List.generate(sorted.length, (i) => FlSpot(i.toDouble(), dateMap[sorted[i]]!.toDouble()));
  }

  List<PieChartSectionData> _sourceSections(Map<String, int> map) {
    final total = map.values.fold(0, (s, v) => s + v);
    const colors = {
      'youtube': Colors.red,
      'soundcloud': Colors.orange,
      'spotify': Colors.green,
    };
    return map.entries.map((e) {
      final pct = (e.value / total) * 100;
      return PieChartSectionData(
        value: e.value.toDouble(),
        title: '${e.key}\n${pct.toStringAsFixed(1)}%',
        color: colors[e.key] ?? Colors.blue,
        radius: 60,
        titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
      );
    }).toList();
  }
}

// ─── Shared stat card ────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(label),
          ],
        ),
      ),
    );
  }
}
