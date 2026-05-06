import 'dart:async';

import 'package:flutter/material.dart';

import 'colour_rarity.dart';

class ColourRewardSessionDialog extends StatefulWidget {
  const ColourRewardSessionDialog({super.key, required this.rewards});

  final List<ColourReward> rewards;

  @override
  State<ColourRewardSessionDialog> createState() => _ColourRewardSessionDialogState();
}

class _ColourRewardSessionDialogState extends State<ColourRewardSessionDialog> {
  int _rewardIndex = 0;
  int _previewStep = 0;
  bool _showSummary = false;
  int _summaryVisibleCount = 0;
  Timer? _summaryTimer;

  List<RarityTier> get _previewTiers {
    final reward = widget.rewards[_rewardIndex];
    return RarityTier.values.take(reward.rarity.index + 1).toList();
  }

  ColourReward get _currentReward => widget.rewards[_rewardIndex];

  bool get _showFinalReveal => _previewStep >= _previewTiers.length;

  @override
  void dispose() {
    _summaryTimer?.cancel();
    super.dispose();
  }

  void _startSummaryReveal() {
    _summaryTimer?.cancel();
    _summaryVisibleCount = 0;
    _summaryTimer = Timer.periodic(const Duration(milliseconds: 110), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_summaryVisibleCount >= widget.rewards.length) {
        timer.cancel();
        return;
      }
      setState(() {
        _summaryVisibleCount += 1;
      });
    });
  }

  void _advance() {
    if (_showSummary) {
      Navigator.of(context).pop(true);
      return;
    }

    if (!_showFinalReveal) {
      setState(() => _previewStep += 1);
      return;
    }

    if (_rewardIndex < widget.rewards.length - 1) {
      setState(() {
        _rewardIndex += 1;
        _previewStep = 0;
      });
      return;
    }

    setState(() {
      _showSummary = true;
    });
    _startSummaryReveal();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reward = _currentReward;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: reward.rarity.glowColor.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: reward.rarity.glowColor.withValues(alpha: 0.24),
              blurRadius: 28,
              spreadRadius: 2,
            ),
          ],
        ),
        child: _showSummary ? _buildSummary(context) : _buildReveal(context, reward),
      ),
    );
  }

  Widget _buildReveal(BuildContext context, ColourReward reward) {
    final cs = Theme.of(context).colorScheme;
    final stage = _showFinalReveal ? reward.rarity : _previewTiers[_previewStep];
    final stageColor = stage.glowColor;
    final progressText = _showFinalReveal
        ? 'Revealed ${_rewardIndex + 1} of ${widget.rewards.length}'
        : 'Pull ${_rewardIndex + 1} of ${widget.rewards.length}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Colour pull session',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Chip(
              label: Text(progressText),
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: Tween<double>(begin: 0.88, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            ),
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: _showFinalReveal
              ? _buildFinalCard(reward, stageColor)
              : _buildQuestionCard(stage.label, stageColor, reward.displayName),
        ),
        const SizedBox(height: 14),
        Text(
          _showFinalReveal
              ? 'That one is yours. Press Next to continue.'
              : 'Press Next to step through the near-miss pull.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _advance,
            child: Text(_showFinalReveal ? 'Next' : 'Next'),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionCard(String label, Color stageColor, String hint) {
    return Container(
      key: ValueKey('question-${_rewardIndex}_$_previewStep'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: stageColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: stageColor.withValues(alpha: 0.7), width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: stageColor.withValues(alpha: 0.12),
              border: Border.all(color: stageColor, width: 4),
            ),
            child: Center(
              child: Text(
                '?',
                style: TextStyle(
                  fontSize: 72,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: stageColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildFinalCard(ColourReward reward, Color stageColor) {
    return Container(
      key: ValueKey('reward-${_rewardIndex}_${reward.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: reward.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: stageColor.withValues(alpha: 0.8), width: 2.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: reward.color,
              boxShadow: [
                BoxShadow(
                  color: reward.color.withValues(alpha: 0.42),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.palette, color: Colors.white, size: 52),
          ),
          const SizedBox(height: 14),
          Text(
            reward.displayName,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Chip(
            label: Text(reward.rarity.label),
            avatar: const Icon(Icons.auto_awesome, size: 16),
            backgroundColor: stageColor.withValues(alpha: 0.14),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final summaryReady = _summaryVisibleCount >= widget.rewards.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'All colours pulled',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          'Everything that dropped this time, popping in one by one.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.3,
          ),
          itemCount: widget.rewards.length,
          itemBuilder: (context, index) {
            final reward = widget.rewards[index];
            final visible = index < _summaryVisibleCount;
            return AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              child: AnimatedScale(
                scale: visible ? 1 : 0.82,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                child: _summaryTile(reward),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: summaryReady ? _advance : null,
            icon: const Icon(Icons.check_circle),
            label: const Text('Claim'),
          ),
        ),
      ],
    );
  }

  Widget _summaryTile(ColourReward reward) {
    return Container(
      decoration: BoxDecoration(
        color: reward.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: reward.rarity.glowColor.withValues(alpha: 0.7)),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: reward.color,
            ),
            child: const Icon(Icons.palette, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reward.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(reward.rarity.label),
              ],
            ),
          ),
        ],
      ),
    );
  }
}