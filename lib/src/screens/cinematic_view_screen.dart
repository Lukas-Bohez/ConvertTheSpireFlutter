import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../screens/player.dart' show PlayerState, PositionUiState;
import '../widgets/ambient_scene.dart';

class CinematicViewScreen extends StatefulWidget {
  const CinematicViewScreen({super.key});

  @override
  State<CinematicViewScreen> createState() => _CinematicViewScreenState();
}

class _CinematicViewScreenState extends State<CinematicViewScreen>
    with SingleTickerProviderStateMixin {
  bool _controlsVisible = true;
  Timer? _hideTimer;
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  void _showControls() {
    _hideTimer?.cancel();
    if (mounted) {
      setState(() => _controlsVisible = true);
      _animController.forward();
      _startHideTimer();
    }
  }

  void _hideControls() {
    _hideTimer?.cancel();
    if (mounted) {
      setState(() => _controlsVisible = false);
      _animController.reverse();
    }
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideControls();
    } else {
      _showControls();
    }
  }

  void _startHideTimer() {
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) _hideControls();
    });
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
    _animController.value = 1.0; // start visible
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            const AmbientScene(),
            FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: SafeArea(
                    child: Column(
                      children: [
                        // Top bar
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => Navigator.of(context).pop(),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.35),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              // Optional: subtle "Cinematic" label
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.movie_filter_outlined,
                                      color: Colors.white70,
                                      size: 14,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Cinematic',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        // Bottom transport with backdrop blur
                        _CinematicTransportOverlay(
                          onInteraction: _showControls,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CinematicTransportOverlay extends StatelessWidget {
  const _CinematicTransportOverlay({required this.onInteraction});

  final VoidCallback onInteraction;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlayerState>();
    final item = state.currentItem;
    final cs = Theme.of(context).colorScheme;

    return ClipRRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title / Artist
              if (item != null) ...[
                Text(
                  item.title ?? item.path.split('/').last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: 0.2,
                    shadows: [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 8,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
                if (item.resolvedArtist.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      item.resolvedArtist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        letterSpacing: 0.1,
                        shadows: [
                          Shadow(
                            color: Colors.black87,
                            blurRadius: 6,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
              ],

              // Progress bar with time labels
              _CinematicProgressBar(
                onInteraction: onInteraction,
              ),

              const SizedBox(height: 10),

              // Transport buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CircleIconButton(
                    icon: Icons.skip_previous_rounded,
                    size: 28,
                    onPressed: () {
                      onInteraction();
                      state.previous(only: state.activeTabFilter);
                    },
                    tooltip: 'Previous',
                  ),
                  const SizedBox(width: 18),
                  _CircleIconButton(
                    icon: state.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 36,
                    backgroundColor: cs.primary.withValues(alpha: 0.3),
                    onPressed: () {
                      onInteraction();
                      state.togglePlay();
                    },
                    tooltip: state.isPlaying ? 'Pause' : 'Play',
                  ),
                  const SizedBox(width: 18),
                  _CircleIconButton(
                    icon: Icons.skip_next_rounded,
                    size: 28,
                    onPressed: () {
                      onInteraction();
                      state.next(only: state.activeTabFilter);
                    },
                    tooltip: 'Next',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CinematicProgressBar extends StatelessWidget {
  const _CinematicProgressBar({required this.onInteraction});

  final VoidCallback onInteraction;

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final h = d.inHours.toString();
      return '$h:${m.padLeft(2, '0')}:$s';
    }
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlayerState>();

    return StreamBuilder<PositionUiState>(
      stream: state.positionUiStream,
      initialData: PositionUiState(
        position: state.position,
        duration: state.duration ?? Duration.zero,
        isSeeking: false,
      ),
      builder: (context, snapshot) {
        final posState = snapshot.data ??
            PositionUiState(
              position: state.position,
              duration: state.duration ?? Duration.zero,
              isSeeking: false,
            );
        final dur = posState.duration;
        final pos = posState.position;
        final progress = dur.inMilliseconds > 0
            ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Slider
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
                thumbColor: Colors.white,
                overlayColor: Colors.white.withValues(alpha: 0.15),
              ),
              child: Slider(
                value: progress,
                onChanged: (v) {
                  onInteraction();
                  final target = Duration(
                    milliseconds: (v * dur.inMilliseconds).round(),
                  );
                  state.seek(target);
                },
              ),
            ),
            // Time labels
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(pos),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontFeatures: const [
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  Text(
                    _formatDuration(dur),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontFeatures: const [
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.size,
    this.backgroundColor,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final double size;
  final Color? backgroundColor;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor ?? Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          padding: EdgeInsets.all(size * 0.35),
          child: Icon(
            icon,
            color: Colors.white,
            size: size,
          ),
        ),
      ),
    );
  }
}
