import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_settings.dart';
import '../models/preview_item.dart';
import '../models/queue_item.dart';
import '../state/app_controller.dart';

class HomeScreen extends StatefulWidget {
  final AppController controller;

  const HomeScreen({super.key, required this.controller});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final Uri _buyMeCoffeeUri = Uri.parse('https://buymeacoffee.com/orokaconner');
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _downloadDirController = TextEditingController();
  final TextEditingController _workersController = TextEditingController();
  final TextEditingController _previewMaxController = TextEditingController();
  final TextEditingController _ffmpegChecksumController = TextEditingController();
  final TextEditingController _retryCountController = TextEditingController();
  final TextEditingController _retryBackoffController = TextEditingController();

  bool _expandPlaylist = false;
  String _downloadFormat = 'MP4';
  bool _settingsInitialized = false;
  File? _convertFile;
  String _convertTarget = 'mp4';

  @override
  void dispose() {
    _urlController.dispose();
    _downloadDirController.dispose();
    _workersController.dispose();
    _previewMaxController.dispose();
    _ffmpegChecksumController.dispose();
    _retryCountController.dispose();
    _retryBackoffController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final settings = widget.controller.settings;
        if (settings != null && !_settingsInitialized) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _initSettings(settings);
          });
        }

        return DefaultTabController(
          length: 5,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Convert the Spire'),
              bottom: const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.search), text: 'Search'),
                  Tab(icon: Icon(Icons.queue_music), text: 'Queue'),
                  Tab(icon: Icon(Icons.settings), text: 'Settings'),
                  Tab(icon: Icon(Icons.transform), text: 'Convert'),
                  Tab(icon: Icon(Icons.list_alt), text: 'Logs'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _buildSearchTab(settings),
                _buildQueueTab(),
                _buildSettingsTab(settings),
                _buildConvertTab(settings),
                _buildLogsTab(),
              ],
            ),
          ),
        );
      },
    );
  }

  void _initSettings(AppSettings settings) {
    _downloadDirController.text = settings.downloadDir;
    _workersController.text = settings.maxWorkers.toString();
    _previewMaxController.text = settings.previewMaxEntries.toString();
    _retryCountController.text = settings.retryCount.toString();
    _retryBackoffController.text = settings.retryBackoffSeconds.toString();
    _expandPlaylist = settings.previewExpandPlaylist;
    _settingsInitialized = true;
  }

  Widget _buildSearchTab(AppSettings? settings) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: 'YouTube URL',
                    border: const OutlineInputBorder(),
                    hintText: 'Enter or paste a YouTube URL',
                    prefixIcon: const Icon(Icons.link),
                    suffixIcon: _urlController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _urlController.clear();
                              });
                            },
                            tooltip: 'Clear URL',
                          )
                        : null,
                  ),
                  onChanged: (value) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.content_paste),
                onPressed: () async {
                  final clipboardData = await Clipboard.getData('text/plain');
                  if (clipboardData != null && clipboardData.text != null) {
                    setState(() {
                      _urlController.text = clipboardData.text!;
                    });
                  }
                },
                tooltip: 'Paste from clipboard',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.settings),
                      const SizedBox(width: 8),
                      Text('Download Options', style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _downloadFormat,
                          decoration: const InputDecoration(
                            labelText: 'Format',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.video_library),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'MP4', child: Text('MP4 (Video)')),
                            DropdownMenuItem(value: 'MP3', child: Text('MP3 (Audio)')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _downloadFormat = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: CheckboxListTile(
                          value: _expandPlaylist,
                          onChanged: (value) {
                            setState(() {
                              _expandPlaylist = value ?? false;
                            });
                          },
                          title: const Text('Expand playlist'),
                          subtitle: const Text('Show all videos'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'YouTube Mix playlists (IDs starting with RD) cannot be expanded.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.orange[800]),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.search),
                  label: const Text('Search / Preview'),
                  onPressed: settings == null || _urlController.text.trim().isEmpty
                      ? null
                      : () => widget.controller.preview(
                            _urlController.text.trim(),
                            _expandPlaylist,
                          ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                  onPressed: settings == null || _urlController.text.trim().isEmpty
                      ? null
                      : () {
                          final url = _urlController.text.trim();
                          if (url.isEmpty) return;
                          final item = widget.controller.previewItems.isNotEmpty
                              ? widget.controller.previewItems.firstWhere(
                                  (p) => p.url == url,
                                  orElse: () => widget.controller.previewItems.first,
                                )
                              : null;
                          if (item != null) {
                            widget.controller.addToQueue(item, _downloadFormat.toLowerCase());
                          } else {
                            widget.controller.addToQueue(
                              PreviewItem(
                                id: url,
                                title: url,
                                url: url,
                                uploader: '',
                                duration: null,
                                thumbnailUrl: null,
                              ),
                              _downloadFormat.toLowerCase(),
                            );
                          }
                          widget.controller.downloadAll();
                        },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (widget.controller.previewLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading preview...'),
                  ],
                ),
              ),
            ),
          if (!widget.controller.previewLoading)
            _buildPreviewList(),
        ],
      ),
    );
  }

  Widget _buildPreviewList() {
    final items = widget.controller.previewItems;
    if (items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.info_outline, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No preview results yet.',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter a YouTube URL above and click Search',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.video_library, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Preview Results (${items.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.select_all),
                  label: const Text('Add All'),
                  onPressed: () {
                    for (final item in items) {
                      widget.controller.addToQueue(item, _downloadFormat.toLowerCase());
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Added ${items.length} items to queue')),
                    );
                  },
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Download All'),
                  onPressed: () {
                    for (final item in items) {
                      widget.controller.addToQueue(item, _downloadFormat.toLowerCase());
                    }
                    widget.controller.downloadAll();
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...items.map(
          (item) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        item.thumbnailUrl!,
                        width: 80,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 80,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _downloadFormat == 'MP4' ? Icons.video_file : Icons.audio_file,
                              color: Colors.grey[600],
                            ),
                          );
                        },
                      ),
                    )
                  : Container(
                      width: 80,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _downloadFormat == 'MP4' ? Icons.video_file : Icons.audio_file,
                        color: Colors.grey[600],
                      ),
                    ),
              title: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.uploader),
                  if (item.duration != null)
                    Text(
                      _formatDuration(item.duration!),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                ],
              ),
              trailing: Wrap(
                spacing: 8,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () {
                      widget.controller.addToQueue(item, _downloadFormat.toLowerCase());
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Added to queue')),
                      );
                    },
                    tooltip: 'Add to queue',
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Download'),
                    onPressed: () {
                      widget.controller.addToQueue(item, _downloadFormat.toLowerCase());
                      widget.controller.downloadAll();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  Widget _buildQueueTab() {
    final items = widget.controller.queue;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.queue_music, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No items in queue',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Add items from the Search tab',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    final completedCount = items.where((i) => i.status.name == 'completed').length;
    final inProgressCount = items.where((i) => i.status.name == 'downloading').length;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Queue Status',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${items.length} total • $inProgressCount downloading • $completedCount completed',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  DropdownButton<String>(
                    value: _downloadFormat,
                    items: const [
                      DropdownMenuItem(value: 'MP4', child: Text('MP4 (Video)')),
                      DropdownMenuItem(value: 'MP3', child: Text('MP3 (Audio)')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _downloadFormat = value;
                      });
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.download_for_offline),
                    label: const Text('Download All'),
                    onPressed: items.isEmpty ? null : () => widget.controller.downloadAll(),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Clear Queue'),
                    onPressed: items.isEmpty
                        ? null
                        : () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Clear Queue'),
                                content: const Text('Are you sure you want to clear all items from the queue?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      for (final item in items) {
                                        widget.controller.removeFromQueue(item);
                                      }
                                      Navigator.pop(context);
                                    },
                                    child: const Text('Clear'),
                                  ),
                                ],
                              ),
                            );
                          },
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final statusColor = _getStatusColor(item.status.name);
              final statusIcon = _getStatusIcon(item.status.name);

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: statusColor.withValues(alpha: 0.2),
                        child: Icon(statusIcon, color: statusColor),
                      ),
                      title: Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  item.status.name.toUpperCase(),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('${item.progress}%'),
                              const SizedBox(width: 8),
                              DropdownButton<String>(
                                value: item.format.toUpperCase(),
                                isDense: true,
                                items: const [
                                  DropdownMenuItem(value: 'MP4', child: Text('MP4')),
                                  DropdownMenuItem(value: 'MP3', child: Text('MP3')),
                                ],
                                onChanged: item.status == DownloadStatus.downloading || 
                                          item.status == DownloadStatus.converting ||
                                          item.status == DownloadStatus.completed
                                    ? null
                                    : (value) {
                                        if (value == null) return;
                                        widget.controller.changeQueueItemFormat(item, value.toLowerCase());
                                      },
                              ),
                            ],
                          ),
                        ],
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.download),
                            onPressed: () => widget.controller.downloadSingle(item),
                            tooltip: 'Download',
                            color: Colors.blue,
                          ),
                          IconButton(
                            icon: const Icon(Icons.pause_circle),
                            onPressed: () => widget.controller.cancelDownload(item),
                            tooltip: 'Pause',
                            color: Colors.orange,
                          ),
                          IconButton(
                            icon: const Icon(Icons.play_circle),
                            onPressed: () => widget.controller.resumeDownload(item),
                            tooltip: 'Resume',
                            color: Colors.green,
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => widget.controller.removeFromQueue(item),
                            tooltip: 'Remove',
                            color: Colors.red,
                          ),
                        ],
                      ),
                    ),
                    if (item.progress > 0 && item.progress < 100)
                      LinearProgressIndicator(
                        value: item.progress / 100,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'downloading':
        return Colors.blue;
      case 'paused':
      case 'cancelled':
        return Colors.orange;
      case 'error':
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Icons.check_circle;
      case 'downloading':
        return Icons.downloading;
      case 'paused':
        return Icons.pause_circle;
      case 'cancelled':
        return Icons.cancel;
      case 'error':
      case 'failed':
        return Icons.error;
      default:
        return Icons.hourglass_empty;
    }
  }

  Widget _buildSettingsTab(AppSettings? settings) {
    if (settings == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          // Download Settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder_outlined),
                      const SizedBox(width: 8),
                      Text('Download Settings', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _downloadDirController,
                          decoration: const InputDecoration(
                            labelText: 'Download folder',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.folder),
                          ),
                          readOnly: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Browse'),
                        onPressed: () async {
                          final result = await FilePicker.platform.getDirectoryPath();
                          if (result != null) {
                            setState(() {
                              _downloadDirController.text = result;
                            });
                            await widget.controller.saveSettings(settings.copyWith(downloadDir: result));
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _workersController,
                    decoration: const InputDecoration(
                      labelText: 'Parallel workers (1-10)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.settings_ethernet),
                      hintText: 'Number of concurrent downloads',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: settings.showNotifications,
                    onChanged: (value) {
                      widget.controller.saveSettings(settings.copyWith(showNotifications: value));
                    },
                    title: const Text('Show notifications'),
                    subtitle: const Text('Display notifications when downloads complete'),
                    secondary: const Icon(Icons.notifications),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Preview Settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.preview),
                      const SizedBox(width: 8),
                      Text('Preview Settings', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _previewMaxController,
                    decoration: const InputDecoration(
                      labelText: 'Max preview items',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.list),
                      hintText: 'Maximum number of items to preview',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: settings.previewExpandPlaylist,
                    onChanged: (value) {
                      widget.controller.saveSettings(settings.copyWith(previewExpandPlaylist: value));
                      setState(() {
                        _expandPlaylist = value;
                      });
                    },
                    title: const Text('Expand playlists by default'),
                    subtitle: const Text('Show all videos in playlists automatically'),
                    secondary: const Icon(Icons.playlist_play),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // FFmpeg Settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.code),
                      const SizedBox(width: 8),
                      Text('FFmpeg Settings', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: settings.autoInstallFfmpeg,
                    onChanged: (value) {
                      widget.controller.saveSettings(settings.copyWith(autoInstallFfmpeg: value));
                    },
                    title: const Text('Auto-install FFmpeg'),
                    subtitle: const Text('Automatically download FFmpeg if not found'),
                    secondary: const Icon(Icons.download_for_offline),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ffmpegChecksumController,
                    decoration: const InputDecoration(
                      labelText: 'FFmpeg SHA256 checksum (optional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.security),
                      hintText: 'For verifying downloads',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.build),
                      label: const Text('Install FFmpeg Manually'),
                      onPressed: () async {
                        final url = await _promptForUrl(context, 'FFmpeg download URL');
                        if (url == null) return;
                        await widget.controller.installFfmpeg(
                          Uri.parse(url),
                          checksum: _ffmpegChecksumController.text.trim(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Retry Settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.refresh),
                      const SizedBox(width: 8),
                      Text('Retry Settings', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: settings.autoRetryInstall,
                    onChanged: (value) {
                      widget.controller.saveSettings(settings.copyWith(autoRetryInstall: value));
                    },
                    title: const Text('Auto-retry installs'),
                    subtitle: const Text('Automatically retry failed downloads'),
                    secondary: const Icon(Icons.replay),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _retryCountController,
                    decoration: const InputDecoration(
                      labelText: 'Retry count',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.repeat),
                      hintText: 'Number of retry attempts',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _retryBackoffController,
                    decoration: const InputDecoration(
                      labelText: 'Retry backoff (seconds)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.timelapse),
                      hintText: 'Wait time between retries',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // About
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline),
                      const SizedBox(width: 8),
                      Text('About', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Convert the Spire Reborn',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 6),
                  const Text('Copyright (c) 2026 Oroka Conner. All rights reserved.'),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    icon: const Icon(Icons.coffee),
                    label: const Text('Buy me a coffee'),
                    onPressed: _openBuyMeCoffee,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    _buyMeCoffeeUri.toString(),
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Save Button
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('Save Settings'),
              onPressed: () {
                final next = settings.copyWith(
                  downloadDir: _downloadDirController.text.trim(),
                  maxWorkers: int.tryParse(_workersController.text.trim()) ?? settings.maxWorkers,
                  previewMaxEntries: int.tryParse(_previewMaxController.text.trim()) ?? settings.previewMaxEntries,
                  retryCount: int.tryParse(_retryCountController.text.trim()) ?? settings.retryCount,
                  retryBackoffSeconds: int.tryParse(_retryBackoffController.text.trim()) ?? settings.retryBackoffSeconds,
                );
                widget.controller.saveSettings(next);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Settings saved successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _openBuyMeCoffee() async {
    final launched = await launchUrl(_buyMeCoffeeUri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the Buy Me a Coffee link.')),
      );
    }
  }

  Widget _buildConvertTab(AppSettings? settings) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.transform),
                      const SizedBox(width: 8),
                      Text('File Converter', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.file_upload),
                    label: const Text('Select file to convert'),
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles();
                      if (result == null || result.files.isEmpty) {
                        return;
                      }
                      final path = result.files.single.path;
                      if (path == null) return;
                      setState(() {
                        _convertFile = File(path);
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_convertFile != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.insert_drive_file, color: Colors.blue),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Selected file:',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  _convertFile!.path.split('\\').last,
                                  style: const TextStyle(fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  _convertFile!.path,
                                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setState(() {
                                _convertFile = null;
                              });
                            },
                            tooltip: 'Clear selection',
                          ),
                        ],
                      ),
                    ),
                  if (_convertFile == null)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                      ),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.file_present, size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 8),
                            Text(
                              'No file selected',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _convertTarget,
                    decoration: const InputDecoration(
                      labelText: 'Convert to format',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.transform),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'mp3', child: Text('MP3 (Audio)')),
                      DropdownMenuItem(value: 'mp4', child: Text('MP4 (Video)')),
                      DropdownMenuItem(value: 'wav', child: Text('WAV (Audio)')),
                      DropdownMenuItem(value: 'png', child: Text('PNG (Image)')),
                      DropdownMenuItem(value: 'jpg', child: Text('JPG (Image)')),
                      DropdownMenuItem(value: 'pdf', child: Text('PDF (Document)')),
                      DropdownMenuItem(value: 'txt', child: Text('TXT (Text)')),
                      DropdownMenuItem(value: 'zip', child: Text('ZIP (Archive)')),
                      DropdownMenuItem(value: 'epub', child: Text('EPUB (E-book)')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _convertTarget = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.sync_alt),
                      label: const Text('Convert File'),
                      onPressed: (_convertFile == null || settings == null)
                          ? null
                          : () => widget.controller.convert(_convertFile!, _convertTarget),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (widget.controller.convertResults.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 8),
                        Text(
                          'Converted Files (${widget.controller.convertResults.length})',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 8),
                    ...widget.controller.convertResults.map(
                      (result) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.file_present),
                          ),
                          title: Text(result.name),
                          subtitle: Text(result.message),
                          trailing: ElevatedButton.icon(
                            icon: const Icon(Icons.save_alt, size: 18),
                            label: const Text('Save'),
                            onPressed: () => widget.controller.saveConvertedResult(result),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLogsTab() {
    return ValueListenableBuilder<List<String>>(
      valueListenable: widget.controller.logs.logs,
      builder: (context, logs, _) {
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.list_alt),
                      const SizedBox(width: 8),
                      Text(
                        'Application Logs (${logs.length})',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear Logs'),
                    onPressed: logs.isEmpty
                        ? null
                        : () {
                            widget.controller.logs.logs.value = [];
                          },
                  ),
                ],
              ),
            ),
            Expanded(
              child: logs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info_outline, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No logs yet',
                            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Activity will be logged here',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        final isError = log.toLowerCase().contains('error') || 
                                       log.toLowerCase().contains('failed');
                        final isWarning = log.toLowerCase().contains('warning');
                        final isSuccess = log.toLowerCase().contains('success') || 
                                         log.toLowerCase().contains('completed');
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 4),
                          color: isError
                              ? Colors.red.withValues(alpha: 0.1)
                              : isWarning
                                  ? Colors.orange.withValues(alpha: 0.1)
                                  : isSuccess
                                      ? Colors.green.withValues(alpha: 0.1)
                                      : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                Icon(
                                  isError
                                      ? Icons.error
                                      : isWarning
                                          ? Icons.warning
                                          : isSuccess
                                              ? Icons.check_circle
                                              : Icons.info,
                                  size: 16,
                                  color: isError
                                      ? Colors.red
                                      : isWarning
                                          ? Colors.orange
                                          : isSuccess
                                              ? Colors.green
                                              : Colors.blue,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    log,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: isError ? Colors.red[700] : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _promptForUrl(BuildContext context, String title) async {
    final controller = TextEditingController();
    String? result;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'https://...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                result = controller.text.trim();
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    return result;
  }
}
