import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:convert_the_spire_reborn/src/vault/services/settings_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_creator_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_service.dart';
import 'package:convert_the_spire_reborn/src/widgets/tv_file_browser.dart';

class CreateTorrentScreen extends StatefulWidget {
  const CreateTorrentScreen({super.key});

  @override
  State<CreateTorrentScreen> createState() => _CreateTorrentScreenState();
}

class _CreateTorrentScreenState extends State<CreateTorrentScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _trackersController = TextEditingController(
    text: TorrentCreatorService.defaultTrackers.join('\n'),
  );
  final TextEditingController _commentController = TextEditingController();

  final List<String> _files = [];
  final List<String> _folders = [];

  int? _pieceSize;
  bool _isPrivate = false;
  bool _isCreating = false;
  bool _pickerBusy = false;
  double _progress = 0.0;
  String _progressText = '';
  String _outputPath = '';

  static const Map<String, int?> _pieceOptions = {
    'Auto (recommended)': null,
    '256 KB': 256 * 1024,
    '512 KB': 512 * 1024,
    '1 MB': 1024 * 1024,
    '2 MB': 2 * 1024 * 1024,
    '4 MB': 4 * 1024 * 1024,
  };

  @override
  void initState() {
    super.initState();
    _outputPath = SettingsService.instance.downloadDestination;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _trackersController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _addFiles() async {
    if (_pickerBusy) return;
    _pickerBusy = true;
    try {
      final selectedPaths = await pickMultipleFilePaths(
        context,
        dialogTitle: 'Select files',
      );
      if (selectedPaths.isEmpty) return;
      setState(() {
        for (final path in selectedPaths) {
          if (!_files.contains(path)) {
            _files.add(path);
          }
        }
        _prefillName();
      });
    } finally {
      _pickerBusy = false;
    }
  }

  Future<void> _addFolder() async {
    if (_pickerBusy) return;
    _pickerBusy = true;
    try {
      final path = await pickDirectoryPath(
        context,
        dialogTitle: 'Select folder',
      );
      if (path == null) return;
      setState(() {
        if (!_folders.contains(path)) {
          _folders.add(path);
        }
        _prefillName();
      });
    } finally {
      _pickerBusy = false;
    }
  }

  Future<void> _changeOutputPath() async {
    if (_pickerBusy) return;
    _pickerBusy = true;
    try {
      final path = await pickDirectoryPath(
        context,
        dialogTitle: 'Select output folder',
      );
      if (path == null) return;
      setState(() {
        _outputPath = path;
      });
    } finally {
      _pickerBusy = false;
    }
  }

  void _prefillName() {
    if (_nameController.text.trim().isNotEmpty) return;
    if (_folders.isNotEmpty) {
      _nameController.text = p.basename(_folders.first);
      return;
    }
    if (_files.isNotEmpty) {
      _nameController.text = p.basenameWithoutExtension(_files.first);
    }
  }

  Future<int> _totalSize() async {
    final entries = await TorrentCreatorService.instance.collectEntries(
      filePaths: _files,
      directoryPaths: _folders,
    );
    return entries.fold<int>(0, (sum, e) => sum + (e['length']! as int));
  }

  String _seedDestinationPath() {
    if (_folders.isNotEmpty) {
      return _folders.first;
    }
    if (_files.isNotEmpty) {
      return File(_files.first).parent.path;
    }
    return _outputPath;
  }

  Future<void> _createTorrent() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Torrent name is required.')),
      );
      return;
    }
    if (_files.isEmpty && _folders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select files or a folder first.')),
      );
      return;
    }
    if (_outputPath.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Output location is required.')),
      );
      return;
    }

    setState(() {
      _isCreating = true;
      _progress = 0.0;
      _progressText = 'Preparing...';
    });

    try {
      final entries = await TorrentCreatorService.instance.collectEntries(
        filePaths: _files,
        directoryPaths: _folders,
      );

      final trackers = _trackersController.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final result = await TorrentCreatorService.instance.createTorrent(
        entries: entries,
        torrentName: _nameController.text.trim(),
        trackers: trackers,
        isPrivate: _isPrivate,
        outputDirectory: _outputPath,
        comment: _commentController.text.trim(),
        selectedPieceSize: _pieceSize,
        onProgress: (progress, message) {
          if (!mounted) return;
          setState(() {
            _progress = progress;
            _progressText = message;
          });
        },
      );

      if (!mounted) return;
      final addToDownloads = await showDialog<bool>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('Torrent Created'),
                // overflow-fix: saved path can be long and overflow dialog body.
                content: SingleChildScrollView(
                  child: Text(
                    'Saved to:\n${result.torrentPath}\n\nAdd to downloads now?',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('No'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Add'),
                  ),
                ],
              );
            },
          ) ??
          false;

      if (addToDownloads) {
        try {
          await TorrentService.instance.addTorrentFromTorrentFile(
            result.torrentPath,
            destinationPath: _seedDestinationPath(),
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Torrent file created, but failed to add to downloads: $e',
              ),
            ),
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created ${p.basename(result.torrentPath)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to create torrent: $e')));
    } finally {
      if (!mounted) return;
      setState(() {
        _isCreating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Torrent')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              const Text(
                'Source',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isCreating ? null : _addFiles,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Files'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isCreating ? null : _addFolder,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Add Folder'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ..._files.map(
                (f) => ListTile(
                  dense: true,
                  title: Text(p.basename(f)),
                  subtitle: Text(f),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isCreating
                        ? null
                        : () => setState(() {
                              _files.remove(f);
                            }),
                  ),
                ),
              ),
              ..._folders.map(
                (d) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.folder),
                  title: Text(p.basename(d)),
                  subtitle: Text(d),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isCreating
                        ? null
                        : () => setState(() {
                              _folders.remove(d);
                            }),
                  ),
                ),
              ),
              FutureBuilder<int>(
                future: _totalSize(),
                builder: (context, snapshot) {
                  final size = snapshot.data ?? 0;
                  return Text('Total size: ${_humanSize(size)}');
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Torrent Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _trackersController,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Trackers (one per line)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _pieceSize,
                decoration: const InputDecoration(
                  labelText: 'Piece Size',
                  border: OutlineInputBorder(),
                ),
                items: _pieceOptions.entries
                    .map(
                      (e) => DropdownMenuItem<int?>(
                        value: e.value,
                        child: Text(e.key),
                      ),
                    )
                    .toList(),
                onChanged: _isCreating
                    ? null
                    : (value) => setState(() => _pieceSize = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _commentController,
                decoration: const InputDecoration(
                  labelText: 'Comment (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                value: _isPrivate,
                onChanged: _isCreating
                    ? null
                    : (value) => setState(() => _isPrivate = value),
                title: const Text('Private Torrent'),
                subtitle: const Text(
                  'Disables DHT and PEX for private trackers',
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                title: const Text('Output Location'),
                subtitle: Text(_outputPath.isEmpty ? 'Not set' : _outputPath),
                trailing: TextButton(
                  onPressed: _isCreating ? null : _changeOutputPath,
                  child: const Text('Change'),
                ),
              ),
              if (_isCreating) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress,
                ),
                const SizedBox(height: 6),
                Text(_progressText),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _isCreating ? null : _createTorrent,
                child: Text(_isCreating ? 'Creating...' : 'Create Torrent'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    double value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(1)} ${units[unit]}';
  }
}
