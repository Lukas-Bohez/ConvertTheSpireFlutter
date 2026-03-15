import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// A simple shimmer grid placeholder matching card aspect used in the home grid.
class ShimmerGrid extends StatelessWidget {
  final int itemCount;
  final double aspectRatio;

  const ShimmerGrid({super.key, this.itemCount = 6, this.aspectRatio = 0.78});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: MediaQuery.of(context).size.width < 500 ? 2 : 4,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: aspectRatio,
      ),
      itemCount: itemCount,
      itemBuilder: (ctx, i) {
        return Shimmer.fromColors(
          baseColor: theme.colorScheme.surfaceContainerHighest,
          highlightColor: theme.colorScheme.surface,
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: Container(color: theme.colorScheme.surfaceContainerHighest)),
                Container(height: 16, margin: const EdgeInsets.all(8), color: theme.colorScheme.surfaceContainerHighest),
              ],
            ),
          ),
        );
      },
    );
  }
}
