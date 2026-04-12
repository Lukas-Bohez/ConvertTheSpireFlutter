import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

class TorrentDragDrop extends StatefulWidget {
  final void Function(String path) onTorrentFile;
  final void Function(String path)? onPath;
  final Widget? child;

  const TorrentDragDrop({
    super.key,
    required this.onTorrentFile,
    this.onPath,
    this.child,
  });

  @override
  State<TorrentDragDrop> createState() => _TorrentDragDropState();
}

class _TorrentDragDropState extends State<TorrentDragDrop> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) async {
        setState(() => _dragging = false);
        for (final file in detail.files) {
          if (file.name.endsWith('.torrent')) {
            widget.onTorrentFile(file.path);
          } else {
            widget.onPath?.call(file.path);
          }
        }
      },
      child:
          widget.child ??
          Container(
            height: 120,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _dragging
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.primary),
            ),
            child: const Center(child: Text('Drag & drop .torrent files here')),
          ),
    );
  }
}
