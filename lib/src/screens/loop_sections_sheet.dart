import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/loop_sections.dart';
import '../utils/l10n.dart';
import 'player.dart';

/// Opens the editor of the current track's looped parts (issue #41). While
/// it is open playback goes anywhere, so the moments it marks can be
/// reached.
Future<void> showLoopSectionsSheet(
    BuildContext context, PlayerState state) async {
  final item = state.currentItem;
  if (item == null) return;
  state.loopEditing = true;
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ChangeNotifierProvider<PlayerState>.value(
        value: state,
        child: LoopSectionsSheet(path: item.path),
      ),
    );
  } finally {
    state.loopEditing = false;
  }
}

/// The looped parts of the file at [path]: marked while it plays with
/// "Start here" and "End here", fine-tuned with a slider, played, deleted.
/// One column that scrolls, so it fits a phone held either way.
class LoopSectionsSheet extends StatefulWidget {
  const LoopSectionsSheet({super.key, required this.path});

  final String path;

  @override
  State<LoopSectionsSheet> createState() => _LoopSectionsSheetState();
}

class _LoopSectionsSheetState extends State<LoopSectionsSheet> {
  /// Where the part being marked starts, between "Start here" and
  /// "End here".
  Duration? _pendingStart;

  /// A part being dragged on its slider, before it is saved.
  int? _draggingIndex;
  RangeValues? _draggingValues;

  Future<void> _save(PlayerState state, List<LoopSection> sections,
      {bool? on}) {
    final current = state.loopSettingsFor(widget.path);
    return state.setLoopSettings(
      widget.path,
      LoopSettings(
        on: on ?? current.on,
        sections:
            LoopSectionStore.normalized(sections, duration: state.duration),
      ),
    );
  }

  void _endHere(PlayerState state) {
    final start = _pendingStart;
    if (start == null) return;
    final end = state.position;
    setState(() => _pendingStart = null);
    if (end - start < LoopSectionStore.minLength) return;
    final sections = state.loopSettingsFor(widget.path).sections;
    // A new part turns looping on: that is what it was marked for.
    unawaited(_save(state, [...sections, LoopSection(start, end)], on: true));
  }

  Future<void> _playPart(PlayerState state, LoopSection part) async {
    await state.seek(part.start);
    if (!state.isPlaying) await state.togglePlay();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlayerState>();
    final settings = state.loopSettingsFor(widget.path);
    final sections = settings.sections;
    final duration = state.duration ?? Duration.zero;
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.loop_rounded, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(l10n.loopParts,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              Switch(
                value: settings.looping,
                onChanged: sections.isEmpty
                    ? null
                    : (on) => _save(state, sections, on: on),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(l10n.loopPartsHelp,
              style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          // Where playback is now, which the buttons mark.
          StreamBuilder<PositionUiState>(
            stream: state.positionUiStream,
            builder: (context, _) => Text(
              '${formatLoopTime(state.position)} / ${formatLoopTime(duration)}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.first_page_rounded),
                label: Text(_pendingStart == null
                    ? l10n.loopStartHere
                    : l10n.loopStartsAt(formatLoopTime(_pendingStart!))),
                onPressed: () => setState(() => _pendingStart = state.position),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.last_page_rounded),
                label: Text(l10n.loopEndHere),
                onPressed: _pendingStart == null ? null : () => _endHere(state),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (sections.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(l10n.loopNoPartsYet,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ),
          for (var i = 0; i < sections.length; i++)
            _partCard(context, state, sections, i, duration),
          if (sections.isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text(l10n.loopDeleteAll),
                onPressed: () => _save(state, const [], on: false),
              ),
            ),
        ],
      ),
    );
  }

  Widget _partCard(BuildContext context, PlayerState state,
      List<LoopSection> sections, int i, Duration duration) {
    final part = sections[i];
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final dragging = _draggingIndex == i ? _draggingValues : null;
    final start = dragging != null
        ? Duration(milliseconds: (dragging.start * 1000).round())
        : part.start;
    final end = dragging != null
        ? Duration(milliseconds: (dragging.end * 1000).round())
        : part.end;
    final maxSeconds = duration.inMilliseconds / 1000;

    List<LoopSection> replaced(LoopSection changed) => [
          for (var j = 0; j < sections.length; j++)
            j == i ? changed : sections[j],
        ];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 4),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: cs.primaryContainer,
                  child: Text('${i + 1}',
                      style: TextStyle(
                          fontSize: 12, color: cs.onPrimaryContainer)),
                ),
                const SizedBox(width: 8),
                // Each end is set to where playback is now by tapping it.
                // Its own width, shrunk only on a screen too narrow for it
                // (a third of the row cut "0:59.6" off on a phone).
                Flexible(
                  flex: 3,
                  child: _TimeChip(
                    time: start,
                    tooltip: l10n.loopSetToNow,
                    onPressed: () => _save(
                        state, replaced(LoopSection(state.position, part.end))),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('–'),
                ),
                Flexible(
                  flex: 3,
                  child: _TimeChip(
                    time: end,
                    tooltip: l10n.loopSetToNow,
                    onPressed: () => _save(state,
                        replaced(LoopSection(part.start, state.position))),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.play_arrow_rounded),
                  tooltip: l10n.loopPlayPart,
                  onPressed: () => _playPart(state, part),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: l10n.loopDeletePart,
                  onPressed: () => _save(state, [...sections]..removeAt(i)),
                ),
              ],
            ),
            if (maxSeconds > 0)
              RangeSlider(
                values: RangeValues(
                  (start.inMilliseconds / 1000).clamp(0, maxSeconds),
                  (end.inMilliseconds / 1000).clamp(0, maxSeconds),
                ),
                max: maxSeconds,
                labels: RangeLabels(formatLoopTime(start), formatLoopTime(end)),
                onChanged: (v) => setState(() {
                  _draggingIndex = i;
                  _draggingValues = v;
                }),
                onChangeEnd: (v) {
                  setState(() {
                    _draggingIndex = null;
                    _draggingValues = null;
                  });
                  unawaited(_save(
                    state,
                    replaced(LoopSection(
                      Duration(milliseconds: (v.start * 1000).round()),
                      Duration(milliseconds: (v.end * 1000).round()),
                    )),
                  ));
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip(
      {required this.time, required this.tooltip, required this.onPressed});

  final Duration time;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: tooltip,
        child: ActionChip(
          label: Text(formatLoopTime(time),
              style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()])),
          visualDensity: VisualDensity.compact,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// m:ss.t, or h:mm:ss.t for long videos: tenths of a second, as the ends
/// of a part can be less than a second from where they should be.
String formatLoopTime(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final tenth = (d.inMilliseconds.remainder(1000) ~/ 100).toString();
  return h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:$s.$tenth'
      : '$m:$s.$tenth';
}
