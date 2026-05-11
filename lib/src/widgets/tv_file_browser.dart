import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../services/folder_history_service.dart';
import 'dpad_focusable_surface.dart';

enum TvFileBrowserMode { file, folder }

Future<String?> pickSingleFilePath(
  BuildContext context, {
  String dialogTitle = 'Select file',
  List<String>? allowedExtensions,
  String? initialDirectory,
}) async {
  if (kIsWeb || !Platform.isAndroid) {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: (allowedExtensions != null && allowedExtensions.isNotEmpty)
          ? FileType.custom
          : FileType.any,
      allowedExtensions: allowedExtensions,
      dialogTitle: dialogTitle,
    );
    return result?.files.single.path;
  }

  // Use last opened folder as initial directory if not specified
  String? resolvedInitialDirectory = initialDirectory;
  if (resolvedInitialDirectory == null || resolvedInitialDirectory.isEmpty) {
    resolvedInitialDirectory = await FolderHistoryService().getLastFolder();
  }

  final result = await TvFileBrowser.pickFile(
    context: context,
    allowedExtensions: allowedExtensions ?? const [],
    title: dialogTitle,
    initialDirectory: resolvedInitialDirectory,
  );

  if (result != null) {
    // Save parent directory to history for next time
    final parentDir = result.split(Platform.pathSeparator)..removeLast();
    if (parentDir.isNotEmpty) {
      await FolderHistoryService().saveLastFolder(parentDir.join(Platform.pathSeparator));
    }
  }

  return result;
}

Future<List<String>> pickMultipleFilePaths(
  BuildContext context, {
  String dialogTitle = 'Select files',
  List<String>? allowedExtensions,
  String? initialDirectory,
}) async {
  // Use FilePicker for all platforms including Android TV
  // (TvFileBrowser is optimized for single file/folder selection)
  final result = await FilePicker.platform.pickFiles(
    allowMultiple: true,
    type: (allowedExtensions != null && allowedExtensions.isNotEmpty)
        ? FileType.custom
        : FileType.any,
    allowedExtensions: allowedExtensions,
    dialogTitle: dialogTitle,
  );
  return result?.files
          .map((f) => f.path)
          .whereType<String>()
          .where((path) => path.isNotEmpty)
          .toList() ??
      const [];
}

Future<String?> pickDirectoryPath(
  BuildContext context, {
  String dialogTitle = 'Select folder',
  String? initialDirectory,
}) async {
  if (kIsWeb || !Platform.isAndroid) {
    return FilePicker.platform.getDirectoryPath(dialogTitle: dialogTitle);
  }

  // On Android, try SAF first (gives access to USB drives), then fall back to directory picker
  try {
    final safPath = await _pickDirectoryUsingSAF();
    if (safPath != null) {
      // Save to history
      await FolderHistoryService().saveLastFolder(safPath);
      return safPath;
    }
  } catch (e) {
    debugPrint('SAF picker failed: $e');
  }

  // Use last opened folder as initial directory if not specified
  String? resolvedInitialDirectory = initialDirectory;
  if (resolvedInitialDirectory == null || resolvedInitialDirectory.isEmpty) {
    resolvedInitialDirectory = await FolderHistoryService().getLastFolder();
  }

  final result = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TvFileBrowser(
        title: dialogTitle,
        allowedExtensions: const [],
        initialDirectory: resolvedInitialDirectory,
        mode: TvFileBrowserMode.folder,
      ),
    ),
  );

  if (result != null) {
    // Save to history
    await FolderHistoryService().saveLastFolder(result);
  }

  return result;
}

/// Invokes Android's Storage Access Framework (SAF) document tree picker
/// Returns the selected directory path, or a SAF tree URI if it's an external location
Future<String?> _pickDirectoryUsingSAF() async {
  const platform = MethodChannel('convert_the_spire/saf');
  try {
    final treeUri = await platform.invokeMethod<String>('pickTree');
    if (treeUri == null || treeUri.isEmpty) {
      return null; // User cancelled
    }
    
    // Try to get the actual filesystem path from the tree URI
    final path = await platform.invokeMethod<String>('getPathFromTreeUri', {
      'treeUri': treeUri,
    });
    
    return path ?? treeUri; // Return path if available, otherwise return URI as fallback
  } catch (e) {
    debugPrint('SAF error: $e');
    return null;
  }
}

class TvFileBrowser extends StatefulWidget {
  final String title;
  final bool allowMultiple;
  final List<String>? allowedExtensions;
  final String? initialDirectory;
  final TvFileBrowserMode mode;

  const TvFileBrowser({
    super.key,
    required this.title,
    this.allowMultiple = false,
    this.allowedExtensions,
    this.initialDirectory,
    this.mode = TvFileBrowserMode.file,
  });

  /// Pick a single file. Returns the file path or null if cancelled.
  static Future<String?> pickFile({
    required BuildContext context,
    required List<String> allowedExtensions,
    String title = 'Select file',
    String? initialDirectory,
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TvFileBrowser(
          title: title,
          allowedExtensions: allowedExtensions,
          initialDirectory: initialDirectory,
          mode: TvFileBrowserMode.file,
        ),
      ),
    );
  }

  /// Pick a folder. Returns the folder path or null if cancelled.
  static Future<String?> pickFolder({
    required BuildContext context,
    String title = 'Select folder',
    String? initialDirectory,
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TvFileBrowser(
          title: title,
          allowedExtensions: const [],
          initialDirectory: initialDirectory,
          mode: TvFileBrowserMode.folder,
        ),
      ),
    );
  }

  @override
  State<TvFileBrowser> createState() => _TvFileBrowserState();
}

class _TvFileBrowserState extends State<TvFileBrowser> {
  late Directory _currentDir;
  List<FileSystemEntity> _entries = const [];
  final Set<String> _selected = <String>{};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentDir = _resolveInitialDirectory();
    _loadEntries();
  }

  Directory _resolveInitialDirectory() {
    final candidates = <String>[
      if (widget.initialDirectory != null && widget.initialDirectory!.isNotEmpty)
        widget.initialDirectory!,
      '/storage/emulated/0',
      '/storage/self/primary',
      '/sdcard',
      '/storage',
    ];

    for (final candidate in candidates) {
      final dir = Directory(candidate);
      if (dir.existsSync()) return dir;
    }

    return Directory.current;
  }

  bool _isAllowedFile(File file) {
    final allowed = widget.allowedExtensions;
    if (allowed == null || allowed.isEmpty) return true;
    final name = file.path.split(Platform.pathSeparator).last.toLowerCase();
    for (final extension in allowed) {
      final needle = '.${extension.toLowerCase()}';
      if (name.endsWith(needle)) return true;
    }
    return false;
  }

  Future<void> _loadEntries() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final all = _currentDir.listSync(followLinks: false);
      final directories = <Directory>[];
      final files = <File>[];

      for (final entity in all) {
        if (entity is Directory) {
          directories.add(entity);
        } else if (widget.mode == TvFileBrowserMode.folder) {
          // Folder mode: show all files so user can navigate to the right folder
          files.add(entity as File);
        } else if (entity is File && _isAllowedFile(entity)) {
          // File mode: filter by allowed extensions
          files.add(entity);
        }
      }

      directories.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
      files.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _entries = <FileSystemEntity>[...directories, ...files];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not open ${_currentDir.path}: $e';
        _entries = const [];
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  String _nameForPath(String path) {
    final pieces = path.split(Platform.pathSeparator);
    if (pieces.isEmpty) return path;
    return pieces.last.isEmpty && pieces.length > 1 ? pieces[pieces.length - 2] : pieces.last;
  }

  Future<bool> _goBack() async {
    final parent = _currentDir.parent;
    if (parent.path == _currentDir.path) return false; // at root
    setState(() {
      _currentDir = parent;
      _selected.clear();
    });
    await _loadEntries();
    return true;
  }

  Future<void> _navigateTo(Directory dir) async {
    setState(() {
      _currentDir = dir;
      _selected.clear();
    });
    await _loadEntries();
  }

  void _onTap(FileSystemEntity entity) {
    if (entity is Directory) {
      // Always navigate into a directory
      _navigateTo(entity);
    } else if (widget.mode == TvFileBrowserMode.file) {
      // File mode: tapping a file returns it immediately
      Navigator.of(context).pop(entity.path);
    }
    // Folder mode: tapping a file does nothing (user must use the "Use this folder" button)
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop && widget.mode == TvFileBrowserMode.folder && _currentDir.parent.path != _currentDir.path) {
          // Prevent pop if we can go back and are in folder mode
          await _goBack();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.title,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (!await _goBack()) {
                if (mounted) Navigator.of(context).pop(null);
              }
            },
          ),
          actions: [
            // "Use this folder" button — only shown in folder mode when inside a dir
            if (widget.mode == TvFileBrowserMode.folder && _currentDir.parent.path != _currentDir.path)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: DpadFocusableSurface(
                  autofocus: false,
                  onSelect: () => Navigator.of(context).pop(_currentDir.path),
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(_currentDir.path),
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: Text(
                      isWide ? 'Use this folder' : 'Select',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
          ],
          // Current path shown as subtitle — truncated on narrow screens
          bottom: _currentDir.parent.path == _currentDir.path
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      child: Text(
                        _currentDir.path,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_error!),
                    )
                  : ListView.builder(
                      itemCount: _entries.length,
                      itemBuilder: (context, index) {
                        final entity = _entries[index];
                        final isDir = entity is Directory;
                        final name = _nameForPath(entity.path);

                        return DpadFocusableSurface(
                          autofocus: index == 0,
                          autoScroll: true,
                          region: 'file-browser',
                          onSelect: () => _onTap(entity),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            leading: Icon(
                              isDir ? Icons.folder : _iconForExtension(p.extension(entity.path)),
                              color: isDir
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface,
                              size: 24,
                            ),
                            title: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            subtitle: !isDir
                                ? FutureBuilder<FileStat>(
                                    future: entity.stat(),
                                    builder: (_, snap) {
                                      if (!snap.hasData) return const SizedBox.shrink();
                                      final mb = snap.data!.size / (1024 * 1024);
                                      return Text(
                                        '${mb.toStringAsFixed(1)} MB',
                                        style: Theme.of(context).textTheme.bodySmall,
                                        overflow: TextOverflow.ellipsis,
                                      );
                                    },
                                  )
                                : null,
                            onTap: () => _onTap(entity),
                          ),
                        );
                      },
                    ),
        ),
      ),
    );
  }

  IconData _iconForExtension(String ext) {
    ext = ext.toLowerCase();
    if ({'.mp3', '.m4a', '.flac', '.wav', '.ogg', '.opus', '.aac', '.wma'}.contains(ext)) {
      return Icons.music_note;
    }
    if ({'.mp4', '.mkv', '.avi', '.webm', '.mov', '.wmv', '.flv', '.m4v'}.contains(ext)) {
      return Icons.videocam;
    }
    return Icons.insert_drive_file;
  }
}
