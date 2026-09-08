import 'package:flutter/material.dart';

/// Persistent mini bar shown at the bottom of the browser when casting is active.
/// Slides in from the bottom with an animated transition.
class CastMiniBar extends StatelessWidget {
  final String deviceName;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onStop;

  const CastMiniBar({
    super.key,
    required this.deviceName,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedSlide(
      offset: Offset.zero,
      duration: const Duration(milliseconds: 300),
      child: Material(
        elevation: 8,
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.cast_connected,
                  color: cs.onPrimaryContainer, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Casting to $deviceName',
                      style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      isPlaying ? 'Playing' : 'Paused',
                      style: TextStyle(
                        color: cs.onPrimaryContainer.withValues(alpha: 0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: cs.onPrimaryContainer,
                ),
                onPressed: onPlayPause,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: Icon(Icons.stop, color: cs.onPrimaryContainer),
                onPressed: onStop,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
