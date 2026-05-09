import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'dpad_focusable_surface.dart';

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

  return showDialog<String>(
    context: context,
    builder: (_) => TvFileBrowser(
      title: dialogTitle,
      allowedExtensions: allowedExtensions,
      initialDirectory: initialDirectory,
    ),
  );
}

Future<List<String>> pickMultipleFilePaths(
  BuildContext context, {
  String dialogTitle = 'Select files',
  List<String>? allowedExtensions,
  String? initialDirectory,
}) async {
  if (kIsWeb || !Platform.isAndroid) {
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

  final selected = await showDialog<List<String>>(
    context: context,
    builder: (_) => TvFileBrowser(
      title: dialogTitle,
      allowMultiple: true,
      allowedExtensions: allowedExtensions,
      initialDirectory: initialDirectory,
    ),
  );
  return selected ?? const [];
}

Future<String?> pickDirectoryPath(
  BuildContext context, {
  String dialogTitle = 'Select folder',
  String? initialDirectory,
}) async {
  if (kIsWeb || !Platform.isAndroid) {
    return FilePicker.platform.getDirectoryPath(dialogTitle: dialogTitle);
  }

  return showDialog<String>(
    context: context,
    builder: (_) => TvFileBrowser(
      title: dialogTitle,
      selectDirectory: true,
      initialDirectory: initialDirectory,
    ),
  );
}

class TvFileBrowser extends StatefulWidget {
  final String title;
  final bool allowMultiple;
  final bool selectDirectory;
  final List<String>? allowedExtensions;
  final String? initialDirectory;

  const TvFileBrowser({
    super.key,
    required this.title,
    this.allowMultiple = false,
    this.selectDirectory = false,
    this.allowedExtensions,
    this.initialDirectory,
  });

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
        } else if (!widget.selectDirectory && entity is File && _isAllowedFile(entity)) {
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

  Future<void> _openParent() async {
    final parent = _currentDir.parent;
    if (parent.path == _currentDir.path) return;
    setState(() {
      _currentDir = parent;
      _selected.clear();
    });
    await _loadEntries();
  }

  Future<void> _openDirectory(Directory dir) async {
    setState(() {
      _currentDir = dir;
      _selected.clear();
    });
    await _loadEntries();
  }

  void _toggleSelected(String path) {
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
      } else {
        if (!widget.allowMultiple) _selected.clear();
        _selected.add(path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(fontWeight: FontWeight.w700);

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      title: Text(widget.title, style: titleStyle),
      content: SizedBox(
        width: 680,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_currentDir.path, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(
              children: [
                DpadFocusableSurface(
                  onSelect: _openParent,
                  child: OutlinedButton.icon(
                    onPressed: _openParent,
                    icon: const Icon(Icons.arrow_upward),
                    label: const Text('Parent'),
                  ),
                ),
                const SizedBox(width: 8),
                DpadFocusableSurface(
                  onSelect: _loadEntries,
                  child: OutlinedButton.icon(
                    onPressed: _loadEntries,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ),
                if (widget.selectDirectory) ...[
                  const SizedBox(width: 8),
                  DpadFocusableSurface(
                    onSelect: () => Navigator.of(context).pop(_currentDir.path),
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(_currentDir.path),
                      icon: const Icon(Icons.check),
                      label: const Text('Use this folder'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Card(
                margin: EdgeInsets.zero,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(_error!),
                          )
                        : ListView.builder(
                            itemCount: _entries.length,
                            itemBuilder: (context, index) {
                              final entity = _entries[index];
                              final isDirectory = entity is Directory;
                              final path = entity.path;
                              final selected = _selected.contains(path);

                              return DpadFocusableSurface(
                                onSelect: () {
                                  if (isDirectory) {
                                    _openDirectory(entity);
                                    return;
                                  }
                                  if (widget.allowMultiple) {
                                    _toggleSelected(path);
                                  } else {
                                    Navigator.of(context).pop(path);
                                  }
                                },
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(
                                    isDirectory ? Icons.folder : Icons.insert_drive_file,
                                    color: isDirectory ? Colors.amber : null,
                                  ),
                                  title: Text(_nameForPath(path)),
                                  subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: widget.allowMultiple && !isDirectory
                                      ? Checkbox(
                                          value: selected,
                                          onChanged: (_) => _toggleSelected(path),
                                        )
                                      : null,
                                  onTap: () {
                                    if (isDirectory) {
                                      _openDirectory(entity);
                                      return;
                                    }
                                    if (widget.allowMultiple) {
                                      _toggleSelected(path);
                                    } else {
                                      Navigator.of(context).pop(path);
                                    }
                                  },
                                ),
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (widget.allowMultiple)
          FilledButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selected.toList()..sort()),
            child: Text('Select (${_selected.length})'),
          ),
      ],
    );
  }
}
