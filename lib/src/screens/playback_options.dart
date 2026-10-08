import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../utils/l10n.dart';
import 'player.dart';

/// The subtitles of what plays: on or off, the files found next to it, any
/// other .srt or .vtt file, and their timing (issue #41).
Future<void> showSubtitlesSheet(BuildContext context, PlayerState state) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ChangeNotifierProvider<PlayerState>.value(
      value: state,
      child: const SubtitlesSheet(),
    ),
  );
}

/// `+0.5 s`, `−1.0 s`.
String formatSubtitleDelay(Duration delay) {
  final seconds = delay.inMilliseconds / 1000;
  final sign = seconds > 0 ? '+' : (seconds < 0 ? '−' : '');
  return '$sign${seconds.abs().toStringAsFixed(1)} s';
}

class SubtitlesSheet extends StatelessWidget {
  const SubtitlesSheet({super.key});

  static const step = Duration(milliseconds: 500);

  Future<void> _pick(PlayerState state) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['srt', 'vtt'],
    );
    final path = picked?.files.single.path;
    if (path != null) await state.useSubtitleFile(path);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlayerState>();
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.closed_caption_rounded, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(l10n.subtitles,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              Switch(
                value: state.hasSubtitles && state.subtitlesOn,
                onChanged: state.hasSubtitles
                    ? (on) => unawaited(state.setSubtitlesOn(on))
                    : null,
              ),
            ],
          ),
          if (state.subtitleOptions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(l10n.subtitlesNoneFound,
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ),
          _SubtitleChoice(
            label: l10n.subtitlesNone,
            selected: state.subtitlePath == null,
            onTap: () => unawaited(state.useSubtitleFile(null)),
          ),
          for (final path in state.subtitleOptions)
            _SubtitleChoice(
              label: p.basename(path),
              detail: p.basename(p.dirname(path)),
              selected: state.subtitlePath == path,
              onTap: () => unawaited(state.useSubtitleFile(path)),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_open_rounded),
            label: Text(l10n.subtitlesChooseFile),
            onPressed: () => _pick(state),
          ),
          if (state.hasSubtitles) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  icon: const Icon(Icons.remove_rounded),
                  tooltip: l10n.subtitlesEarlier,
                  onPressed: () => unawaited(
                      state.setSubtitleDelay(state.subtitleDelay - step)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    l10n.subtitlesTiming(
                        formatSubtitleDelay(state.subtitleDelay)),
                    style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.add_rounded),
                  tooltip: l10n.subtitlesLater,
                  onPressed: () => unawaited(
                      state.setSubtitleDelay(state.subtitleDelay + step)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SubtitleChoice extends StatelessWidget {
  const _SubtitleChoice(
      {required this.label,
      required this.selected,
      required this.onTap,
      this.detail});

  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: SizedBox(
        width: 24,
        child: selected
            ? Icon(Icons.check_rounded,
                color: Theme.of(context).colorScheme.primary)
            : null,
      ),
      title: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: detail == null
          ? null
          : Text(detail!, maxLines: 1, overflow: TextOverflow.ellipsis),
      contentPadding: EdgeInsets.zero,
      dense: true,
      onTap: onTap,
    );
  }
}

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
