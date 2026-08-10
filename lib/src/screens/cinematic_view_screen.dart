import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../screens/player.dart' show PlayerState, MediaItem, MediaType;
import '../widgets/ambient_scene.dart';

class CinematicViewScreen extends StatefulWidget {
  const CinematicViewScreen({super.key});

  @override
  State<CinematicViewScreen> createState() => _CinematicViewScreenState();
}

class _CinematicViewScreenState extends State<CinematicViewScreen> {
  bool _controlsVisible = true;
  Timer? _hideTimer;

  void _showControls() {
    setState(() => _controlsVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  @override
  void initState() {
    super.initState();
    _showControls();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Theme(
        data: Theme.of(context).copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _showControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const AmbientScene(),
              AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 400),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: SafeArea(
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.topLeft,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            tooltip: 'Close cinematic view',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                        const Spacer(),
                        _CinematicTransportOverlay(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CinematicTransportOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlayerState>();
    final item = state.currentItem;
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item != null) ...[
            Text(
              item.title ?? item.path.split('/').last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            if (item.resolvedArtist.isNotEmpty)
              Text(
                item.resolvedArtist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded,
                    color: Colors.white),
                onPressed: () => state.previous(only: state.activeTabFilter),
                tooltip: 'Previous',
              ),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    state.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                  onPressed: state.togglePlay,
                  tooltip: state.isPlaying ? 'Pause' : 'Play',
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon:
                    const Icon(Icons.skip_next_rounded, color: Colors.white),
                onPressed: () => state.next(only: state.activeTabFilter),
                tooltip: 'Next',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
