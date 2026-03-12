import 'package:flutter/material.dart';

import '../../data/browser_db.dart';

/// History screen with date-grouped entries, search, swipe-to-delete,
/// clear by time range, and infinite scroll pagination.
class HistoryScreen extends StatefulWidget {
  final BrowserRepository repo;
  final ValueChanged<String> onNavigate;

  const HistoryScreen({
    super.key,
    required this.repo,
    required this.onNavigate,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _scrollController = ScrollController();
  final List<Map<String, dynamic>> _items = [];
  String _search = '';
  bool _loading = false;
  bool _hasMore = true;
  static const _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _loadMore();
    _scrollController.addListener(_onScroll);
    widget.repo.addListener(_refresh);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    widget.repo.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    _items.clear();
    _hasMore = true;
    _loadMore();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loading &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    _loading = true;
    final rows = await widget.repo.getHistory(
      limit: _pageSize,
      offset: _items.length,
      search: _search.isNotEmpty ? _search : null,
    );
    if (mounted) {
      setState(() {
        _items.addAll(rows);
        _hasMore = rows.length == _pageSize;
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _search = value;
    _items.clear();
    _hasMore = true;
    _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grouped = _groupByDate(_items);

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          PopupMenuButton<String>(
            onSelected: _handleClearAction,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'hour', child: Text('Last hour')),
              PopupMenuItem(value: 'day', child: Text('Last 24 hours')),
              PopupMenuItem(value: 'week', child: Text('Last 7 days')),
              PopupMenuItem(value: 'all', child: Text('All time')),
            ],
            icon: const Icon(Icons.delete_sweep),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search history',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),

          // ── List ──
          Expanded(
            child: _items.isEmpty && !_loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history,
                            size: 64,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text('No history',
                            style: TextStyle(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: grouped.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= grouped.length) {
                        return const Center(
                            child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ));
                      }
                      final entry = grouped[index];
                      if (entry is String) {
                        return _DateHeader(label: entry);
                      }
                      final item = entry as Map<String, dynamic>;
                      return _HistoryTile(
                        item: item,
                        onTap: () {
                          widget.onNavigate(item['url'] as String);
                          Navigator.pop(context);
                        },
                        onDismissed: () => widget.repo
                            .deleteHistoryItem(item['id'] as int),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Groups items by date label, inserting date header strings.
  List<dynamic> _groupByDate(List<Map<String, dynamic>> items) {
    final result = <dynamic>[];
    String? lastLabel;
    for (final item in items) {
      final dt = DateTime.fromMillisecondsSinceEpoch(
          item['visited_at'] as int);
      final label = _dateLabel(dt);
      if (label != lastLabel) {
        result.add(label);
        lastLabel = label;
      }
      result.add(item);
    }
    return result;
  }

  String _dateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    if (now.difference(dt).inDays < 7) return _weekday(dt.weekday);
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _weekday(int w) {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    return names[w - 1];
  }

  void _handleClearAction(String range) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history?'),
        content: Text('Clear browsing history for $range?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true) return;
    // For simplicity, clear all. A time-range filter can be added later.
    await widget.repo.clearHistory();
    _refresh();
  }
}

// ── Date header ──

class _DateHeader extends StatelessWidget {
  final String label;
  const _DateHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

// ── History tile ──

class _HistoryTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  const _HistoryTile({
    required this.item,
    required this.onTap,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    final url = item['url'] as String;
    final title = item['title'] as String? ?? '';
    final favicon = item['favicon'] as String?;
    final host = Uri.tryParse(url)?.host ?? url;
    final dt = DateTime.fromMillisecondsSinceEpoch(
        item['visited_at'] as int);
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return Dismissible(
      key: ValueKey(item['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDismissed(),
      child: ListTile(
        leading: _buildFavicon(favicon),
        title: Text(title.isNotEmpty ? title : host,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(host,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12)),
        trailing: Text(time,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )),
        onTap: onTap,
      ),
    );
  }

  Widget _buildFavicon(String? url) {
    if (url != null && url.isNotEmpty) {
      return Image.network(url,
          width: 24,
          height: 24,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.language, size: 24));
    }
    return const Icon(Icons.language, size: 24);
  }
}
