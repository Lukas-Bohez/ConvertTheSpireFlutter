import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../screens/player.dart';
import '../services/pip_service.dart';

/// Shows only the playing video while Android has the app in its
/// picture-in-picture window (issue #45, fix 11): the whole app used to be
/// shrunk into it, which looked like a tiny screenshot. The app stays as it
/// was underneath, so coming back finds it unchanged.
class PipFrame extends StatelessWidget {
  const PipFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!PipService.platformSupported) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: PipService.instance.inPip,
      builder: (context, inPip, _) {
        if (!inPip) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            const Positioned.fill(child: _PipVideo()),
          ],
        );
      },
    );
  }
}

class _PipVideo extends StatelessWidget {
  const _PipVideo();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlayerState>();
    final mk = state.videoController;
    final android = state.androidVideoController;
    Widget video = const SizedBox.shrink();
    if (mk != null) {
      video = Video(
        controller: mk,
        controls: NoVideoControls,
        subtitleViewConfiguration:
            const SubtitleViewConfiguration(visible: false),
      );
    } else if (android != null && android.value.isInitialized) {
      video = Center(
        child: AspectRatio(
          aspectRatio: android.value.aspectRatio,
          child: VideoPlayer(android),
        ),
      );
    }
    return ColoredBox(color: Colors.black, child: video);
  }
}
