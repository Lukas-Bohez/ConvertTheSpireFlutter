import 'package:flutter/material.dart';
import '../utils/l10n.dart';
import 'shimmer_grid.dart';

/// A reusable Material 3 home grid showing media cards.
class M3HomeGrid<T> extends StatelessWidget {
  final bool loading;
  final List<T> items;
  final Widget Function(BuildContext, T) itemBuilder;
  final VoidCallback? onRetry;

  const M3HomeGrid({
    super.key,
    required this.loading,
    required this.items,
    required this.itemBuilder,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (loading) return const ShimmerGrid();
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_music, size: 64, color: cs.outline),
            const SizedBox(height: 12),
            Text(context.l10n.noMediaYet, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            FilledButton(onPressed: onRetry, child: Text(context.l10n.scanLibrary)),
          ],
        ),
      );
    }

    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width < 500 ? 2 : (width < 900 ? 3 : 5);
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) => itemBuilder(ctx, items[i]),
    );
  }
}
