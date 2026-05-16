import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart' as win32;

import '../services/android_saf.dart';
import '../services/folder_history_service.dart';

enum TvFileBrowserMode { file, folder }

Future<String?> pickSingleFilePath(
  BuildContext context, {
  String dialogTitle = 'Select file',
  List<String>? allowedExtensions,
  String? initialDirectory,
}) async {
  if (kIsWeb) {
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
  if (kIsWeb) {
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

  final initial = initialDirectory == null || initialDirectory.isEmpty
      ? await FolderHistoryService().getLastFolder()
      : initialDirectory;

  final chosen = await TvFileBrowser.pickFile(
    context: context,
    allowedExtensions: allowedExtensions ?? const [],
    title: dialogTitle,
    initialDirectory: initial,
  );
  if (chosen == null) return const [];
  return [chosen];
}

Future<String?> pickDirectoryPath(
  BuildContext context, {
  String dialogTitle = 'Select folder',
  String? initialDirectory,
}) async {
  if (kIsWeb) {
    return FilePicker.platform.getDirectoryPath(dialogTitle: dialogTitle);
  }

  return _pickDirectoryWithBuiltInBrowser(
    context,
    dialogTitle: dialogTitle,
    initialDirectory: initialDirectory,
  );
}

Future<String?> _pickDirectoryWithBuiltInBrowser(
  BuildContext context, {
  required String dialogTitle,
  String? initialDirectory,
}) async {
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
    await FolderHistoryService().saveLastFolder(result);
  }

  return result;
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
  final Set<String> _selected = <String>{};
  List<FileSystemEntity> _entries = const [];
  List<_StorageLocation> _storageLocations = const [];
  bool _loading = false;
  bool _loadingStorageLocations = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentDir = _resolveInitialDirectory();
    _loadEntries();
    _loadStorageLocations();
  }

  Directory _resolveInitialDirectory() {
    final candidates = <String>[
      if (widget.initialDirectory != null && widget.initialDirectory!.isNotEmpty)
        widget.initialDirectory!,
      if (Platform.isAndroid) '/storage/emulated/0',
      if (Platform.isAndroid) '/storage/self/primary',
      if (Platform.isAndroid) '/sdcard',
      if (Platform.isWindows) 'C:${Platform.pathSeparator}',
      if (Platform.isMacOS) '/',
      if (Platform.isLinux) '/',
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
      _entries = const [];
    });

    try {
      final directories = <Directory>[];
      final files = <File>[];
      var scanned = 0;

      await for (final entity in _currentDir.list(followLinks: false)) {
        if (entity is Directory) {
          directories.add(entity);
        } else if (entity is File && widget.mode == TvFileBrowserMode.folder) {
          files.add(entity);
        } else if (entity is File && _isAllowedFile(entity)) {
          files.add(entity);
        }

        scanned++;
        if (scanned % 200 == 0 && mounted) {
          directories.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
          files.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
          setState(() {
            _entries = <FileSystemEntity>[...directories, ...files];
          });
          await Future<void>.delayed(Duration.zero);
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

  Future<void> _loadStorageLocations() async {
    if (_loadingStorageLocations) return;
    _loadingStorageLocations = true;

    try {
      final locations = _discoverStorageLocations();
      if (Platform.isAndroid) {
        final volumes = await AndroidSaf().getExternalVolumes();
        for (final volume in volumes) {
          final path = volume['path']?.trim() ?? '';
          if (path.isEmpty) continue;
          final label = volume['label']?.trim().isNotEmpty == true
              ? volume['label']!.trim()
              : 'USB Drive';
          locations.add(_StorageLocation(
            label: label,
            path: path,
            icon: Icons.usb,
            preferSafFallback: true,
          ));
        }
        locations.addAll(_discoverAndroidStorageLocations());
      }

      if (!mounted) return;
      setState(() {
        _storageLocations = locations;
      });
    } catch (_) {
      // Best effort only.
    } finally {
      _loadingStorageLocations = false;
    }
  }

  List<_StorageLocation> _discoverStorageLocations() {
    final locations = <_StorageLocation>[];

    if (Platform.isWindows) {
      final driveMask = win32.GetLogicalDrives();
      for (var code = 0; code < 26; code++) {
        if ((driveMask & (1 << code)) == 0) continue;
        final letter = String.fromCharCode(65 + code);
        final path = '$letter:${Platform.pathSeparator}';
        locations.add(_StorageLocation(label: '$letter drive', path: path, icon: Icons.storage));
      }
      return locations;
    }

    if (Platform.isMacOS) {
      locations.add(_StorageLocation(label: 'Mac', path: '/', icon: Icons.storage));
      final volumes = Directory('/Volumes');
      if (volumes.existsSync()) {
        final children = volumes.listSync(followLinks: false).whereType<Directory>().toList();
        children.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
        for (final child in children) {
          locations.add(_StorageLocation(
            label: _nameForPath(child.path),
            path: child.path,
            icon: Icons.usb,
          ));
        }
      }
      return locations;
    }

    if (Platform.isLinux) {
      locations.add(_StorageLocation(label: 'Root', path: '/', icon: Icons.storage));
      for (final mountRoot in ['/mnt', '/media', '/run/media']) {
        final root = Directory(mountRoot);
        if (!root.existsSync()) continue;
        final children = root.listSync(followLinks: false).whereType<Directory>().toList();
        children.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
        for (final child in children) {
          locations.add(_StorageLocation(
            label: _nameForPath(child.path),
            path: child.path,
            icon: Icons.usb,
          ));
        }
      }
      return locations;
    }

    if (Platform.isAndroid) {
      locations.addAll(_discoverAndroidStorageLocations());
    }

    return locations;
  }

  List<_StorageLocation> _discoverAndroidStorageLocations() {
    final locations = <_StorageLocation>[];
    final candidates = <Map<String, Object>>[
      {'label': 'Device storage', 'path': '/storage/emulated/0', 'icon': Icons.phone_android},
      {'label': 'Primary storage', 'path': '/storage/self/primary', 'icon': Icons.phone_android},
      {'label': 'SD card', 'path': '/sdcard', 'icon': Icons.sd_storage},
    ];

    for (final candidate in candidates) {
      final path = candidate['path'] as String;
      final dir = Directory(path);
      if (dir.existsSync()) {
        locations.add(_StorageLocation(
          label: candidate['label'] as String,
          path: dir.path,
          icon: candidate['icon'] as IconData,
          preferSafFallback: false,
        ));
      }
    }

    for (final rootPath in ['/storage', '/mnt/media_rw']) {
      final root = Directory(rootPath);
      if (!root.existsSync()) continue;
      final children = root.listSync(followLinks: false).whereType<Directory>().toList();
      children.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
      for (final child in children) {
        if (child.path == '/storage/emulated' || child.path == '/storage/self') continue;
        final label = _nameForPath(child.path);
        if (label.isEmpty) continue;
        locations.add(_StorageLocation(
          label: label,
          path: child.path,
          icon: Icons.usb,
          preferSafFallback: true,
        ));
      }
    }

    return locations;
  }

  String _nameForPath(String path) {
    final pieces = path.split(Platform.pathSeparator);
    if (pieces.isEmpty) return path;
    return pieces.last.isEmpty && pieces.length > 1 ? pieces[pieces.length - 2] : pieces.last;
  }

  Future<bool> _goBack() async {
    final parent = _currentDir.parent;
    if (parent.path == _currentDir.path) return false;
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

  Future<void> _openStorageLocation(_StorageLocation location) async {
    final dir = Directory(location.path);
    if (!dir.existsSync()) {
      if (Platform.isAndroid && location.preferSafFallback) {
        final picked = await AndroidSaf().pickTree();
        if (picked != null && mounted) {
          Navigator.of(context).pop(picked);
        }
        return;
      }
      if (mounted) {
        setState(() {
          _error = 'Storage location not available: ${location.label}';
        });
      }
      return;
    }
    await _navigateTo(dir);
    if (Platform.isAndroid && location.preferSafFallback && _error != null) {
      final picked = await AndroidSaf().pickTree();
      if (picked != null && mounted) {
        Navigator.of(context).pop(picked);
      }
    }
  }

  bool _isCurrentStorageLocation(_StorageLocation location) {
    final current = _currentDir.path.toLowerCase();
    final root = location.path.toLowerCase();
    return current == root || current.startsWith('$root${Platform.pathSeparator}');
  }

  void _onTap(FileSystemEntity entity) {
    if (entity is Directory) {
      _navigateTo(entity);
    } else if (widget.mode == TvFileBrowserMode.file) {
      Navigator.of(context).pop(entity.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop && widget.mode == TvFileBrowserMode.folder && _currentDir.parent.path != _currentDir.path) {
          await _goBack();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title, overflow: TextOverflow.ellipsis, maxLines: 1),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (!await _goBack()) {
                if (mounted) Navigator.of(context).pop(null);
              }
            },
          ),
          actions: [
            if (widget.mode == TvFileBrowserMode.folder && _currentDir.parent.path != _currentDir.path)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(_currentDir.path),
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: Text(isWide ? 'Use this folder' : 'Select', overflow: TextOverflow.ellipsis),
                ),
              ),
          ],
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
          child: Column(
            children: [
              if (_storageLocations.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: SizedBox(
                    height: 40,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final location in _storageLocations)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(location.icon, size: 18),
                                    const SizedBox(width: 8),
                                    Text(location.label),
                                  ],
                                ),
                                selected: _isCurrentStorageLocation(location),
                                onSelected: (_) => _openStorageLocation(location),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              Expanded(
                child: _error != null
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

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            leading: Icon(
                              isDir ? Icons.folder : _iconForExtension(p.extension(entity.path)),
                              color: isDir
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface,
                              size: 24,
                            ),
                            title: Text(name, overflow: TextOverflow.ellipsis, maxLines: 1),
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
                          );
                        },
                      ),
              ),
            ],
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

class _StorageLocation {
  final String label;
  final String path;
  final IconData icon;
  final bool preferSafFallback;

  const _StorageLocation({
    required this.label,
    required this.path,
    required this.icon,
    this.preferSafFallback = false,
  });
}
