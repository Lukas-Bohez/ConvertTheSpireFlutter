import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/l10n.dart';
import 'player.dart';

/// `1.5×`: a speed as the player shows it.
String formatSpeed(double speed) {
  final text = speed.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return '$text×';
}

/// Picks how fast media plays.
Future<void> showSpeedDialog(BuildContext context, PlayerState state) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text(context.l10n.playbackSpeed),
      children: [
        for (final speed in PlayerState.speeds)
          _Choice(
            label: formatSpeed(speed),
            selected: state.speed == speed,
            onTap: () {
              unawaited(state.setSpeed(speed));
              Navigator.pop(dialogContext);
            },
          ),
      ],
    ),
  );
}

/// Picks when playback pauses by itself.
Future<void> showSleepTimerDialog(BuildContext context, PlayerState state) {
  final l10n = context.l10n;
  final active = state.sleepAt != null || state.sleepAtTrackEnd;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      void pick(VoidCallback action) {
        action();
        Navigator.pop(dialogContext);
      }

      return SimpleDialog(
        title: Text(l10n.sleepTimer),
        children: [
          _Choice(
            label: l10n.sleepTimerOff,
            selected: !active,
            onTap: () => pick(() => state.setSleepTimer(null)),
          ),
          for (final minutes in const [15, 30, 45, 60])
            _Choice(
              label: l10n.sleepTimerMinutes(minutes),
              selected: false,
              onTap: () =>
                  pick(() => state.setSleepTimer(Duration(minutes: minutes))),
            ),
          _Choice(
            label: l10n.sleepTimerEndOfTrack,
            selected: state.sleepAtTrackEnd,
            onTap: () => pick(state.setSleepAtTrackEnd),
          ),
        ],
      );
    },
  );
}

class _Choice extends StatelessWidget {
  const _Choice(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SimpleDialogOption(
      onPressed: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: selected
                ? Icon(Icons.check_rounded,
                    color: Theme.of(context).colorScheme.primary)
                : null,
          ),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

/// The sleep timer counting down, while it runs; tapping it changes it,
/// its cross turns it off.
class SleepTimerChip extends StatefulWidget {
  const SleepTimerChip({super.key, required this.state});

  final PlayerState state;

  @override
  State<SleepTimerChip> createState() => _SleepTimerChipState();
}

class _SleepTimerChipState extends State<SleepTimerChip> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final at = state.sleepAt;
    final String label;
    if (at != null) {
      var left = at.difference(DateTime.now());
      if (left.isNegative) left = Duration.zero;
      final m = left.inMinutes;
      final s = left.inSeconds.remainder(60).toString().padLeft(2, '0');
      label = context.l10n.sleepTimerIn('$m:$s');
    } else {
      label = context.l10n.sleepAfterTrack;
    }
    return InputChip(
      avatar: const Icon(Icons.bedtime_outlined, size: 16),
      label: Text(label, overflow: TextOverflow.ellipsis),
      visualDensity: VisualDensity.compact,
      onPressed: () => showSleepTimerDialog(context, state),
      onDeleted: () => state.setSleepTimer(null),
      deleteButtonTooltipMessage: context.l10n.sleepTimerOff,
    );
  }
}
