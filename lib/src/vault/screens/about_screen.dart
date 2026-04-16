import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:convert_the_spire_reborn/src/state/app_controller.dart';
import 'package:convert_the_spire_reborn/src/vault/constants.dart';
import 'package:convert_the_spire_reborn/src/vault/platform/desktop_window.dart';
import 'package:convert_the_spire_reborn/src/vault/services/ai_copilot_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/settings_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/theme_service.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final bool _androidTorrentOnly =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  late final SettingsService _settings;
  late final TextEditingController _ollamaUrlController;
  late final TextEditingController _downloadDirController;
  late final TextEditingController _listenPortController;
  late final TextEditingController _maxGlobalController;
  late final TextEditingController _maxPerTorrentController;
  late final TextEditingController _maxActiveController;
  late final TextEditingController _downloadRateController;
  late final TextEditingController _uploadRateController;
  late AiCopilotService _aiService;

  List<String> _availableModels = <String>[];
  String? _selectedModel;
  bool _loadingModels = false;
  bool _downloadingRecommended = false;
  String _modelStatus = '';
  bool _savingNetwork = false;
  bool _pickerBusy = false;
  ThemeMode _themeMode = ThemeMode.system;

  String? _androidDocumentsUriForPath(String directoryPath) {
    final normalized = directoryPath.replaceAll('\\', '/');
    const prefixes = <String>['/storage/emulated/0/', '/sdcard/'];
    for (final prefix in prefixes) {
      if (normalized.startsWith(prefix)) {
        final relative = normalized.substring(prefix.length);
        final encodedDocId = Uri.encodeComponent('primary:$relative');
        return 'content://com.android.externalstorage.documents/document/$encodedDocId';
      }
    }
    return null;
  }

  Future<bool> _tryOpenFolderOnAndroid(String directoryPath) async {
    final docUri = _androidDocumentsUriForPath(directoryPath);
    if (docUri != null) {
      try {
        if (await launchUrl(
          Uri.parse(docUri),
          mode: LaunchMode.externalApplication,
        )) {
          return true;
        }
      } catch (_) {
        // Fall through to file URI fallback.
      }
    }

    try {
      if (await launchUrl(
        Uri.file(directoryPath),
        mode: LaunchMode.externalApplication,
      )) {
        return true;
      }
    } catch (_) {
      // Keep fallback snackbar path below.
    }

    return false;
  }

  @override
  void initState() {
    super.initState();
    _settings = SettingsService.instance;
    _ollamaUrlController = TextEditingController(text: _settings.aiOllamaUrl);
    _downloadDirController = TextEditingController(
      text: _settings.downloadDestination,
    );
    _listenPortController = TextEditingController(
      text: '${_settings.listenPort}',
    );
    _maxGlobalController = TextEditingController(
      text: '${_settings.maxConnectionsGlobal}',
    );
    _maxPerTorrentController = TextEditingController(
      text: '${_settings.maxConnectionsPerTorrent}',
    );
    _maxActiveController = TextEditingController(
      text: '${_settings.maxActiveDownloads}',
    );
    _downloadRateController = TextEditingController(
      text: '${_settings.downloadRateLimitKib}',
    );
    _uploadRateController = TextEditingController(
      text: '${_settings.uploadRateLimitKib}',
    );
    _selectedModel = _settings.aiDefaultModel;
    _themeMode = ThemeService.instance.themeMode;
    if (!_androidTorrentOnly) {
      _aiService = AiCopilotService(baseUrl: _settings.aiOllamaUrl);
      _fetchAvailableModels();
    }
  }

  ThemeMode _themeModeFromString(String? mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  AppController? _maybeAppController() {
    try {
      return context.read<AppController>();
    } catch (_) {
      return null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appController = _maybeAppController();
    final mode = _themeModeFromString(appController?.settings?.themeMode);
    if (mode != _themeMode) {
      _themeMode = mode;
    }
  }

  @override
  void dispose() {
    _ollamaUrlController.dispose();
    _downloadDirController.dispose();
    _listenPortController.dispose();
    _maxGlobalController.dispose();
    _maxPerTorrentController.dispose();
    _maxActiveController.dispose();
    _downloadRateController.dispose();
    _uploadRateController.dispose();
    super.dispose();
  }

  Future<void> _fetchAvailableModels() async {
    if (_androidTorrentOnly) return;
    setState(() {
      _loadingModels = true;
      _modelStatus = 'Fetching models...';
    });

    try {
      final models = await _aiService.fetchModels();
      if (!mounted) return;
      setState(() {
        _availableModels = models;
        _loadingModels = false;
        if (models.isEmpty) {
          _modelStatus = 'No models detected from host.';
        } else {
          _modelStatus = 'Successfully fetched ${models.length} model(s)';
          if (_selectedModel == null ||
              !_availableModels.contains(_selectedModel)) {
            _selectedModel = _availableModels.contains(kDefaultAiModel)
                ? kDefaultAiModel
                : _availableModels.first;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _availableModels = <String>[];
        _loadingModels = false;
        _modelStatus = 'Failed to fetch models: $e';
      });
    }
  }

  Future<void> _onUrlChanged() async {
    if (_androidTorrentOnly) return;
    final newUrl = _ollamaUrlController.text.trim();
    if (newUrl.isEmpty) return;

    _aiService.setBaseUrl(newUrl);
    await _fetchAvailableModels();
  }

  Future<void> _saveAiSettings() async {
    if (_androidTorrentOnly) return;
    await _settings.setAiOllamaUrl(_ollamaUrlController.text);
    await _settings.setAiDefaultModel(_selectedModel ?? kDefaultAiModel);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('AI settings saved')));
  }

  Future<void> _downloadRecommendedModel() async {
    if (_androidTorrentOnly) return;
    if (_downloadingRecommended) return;
    setState(() {
      _downloadingRecommended = true;
      _modelStatus = 'Downloading recommended model $kDefaultAiModel...';
    });

    try {
      await for (final event in _aiService.pullModelStream(kDefaultAiModel)) {
        final status = (event['status'] ?? '').toString();
        final total = (event['total'] as num?)?.toDouble() ?? 0;
        final completed = (event['completed'] as num?)?.toDouble() ?? 0;
        final progress = total > 0 ? (completed / total * 100) : 0.0;
        if (!mounted) return;
        setState(() {
          _modelStatus = progress > 0
              ? '$status (${progress.toStringAsFixed(1)}%)'
              : status;
        });
      }
      await _fetchAvailableModels();
      _selectedModel = kDefaultAiModel;
      await _settings.setAiDefaultModel(kDefaultAiModel);
      if (!mounted) return;
      setState(() {
        _modelStatus = 'Recommended model is ready and selected.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modelStatus = 'Recommended model download failed: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _downloadingRecommended = false;
      });
    }
  }

  Future<void> _openDownloadFolder() async {
    final pathToOpen = _downloadDirController.text.trim();
    if (pathToOpen.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No download folder set.')));
      return;
    }

    String directoryPath;

    if (Directory(pathToOpen).existsSync()) {
      directoryPath = pathToOpen;
    } else if (File(pathToOpen).existsSync()) {
      directoryPath = File(pathToOpen).parent.path;
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download folder does not exist.')),
      );
      return;
    }

    if (Platform.isAndroid) {
      final opened = await _tryOpenFolderOnAndroid(directoryPath);
      if (opened) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to open folder automatically. Files saved to: $directoryPath',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

    if (Platform.isWindows) {
      try {
        await Process.start(
          'explorer.exe',
          <String>[directoryPath],
          mode: ProcessStartMode.detached,
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to open folder.')),
        );
      }
      return;
    }

    final uri = Uri.file(directoryPath);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to open folder.')));
    }
  }

  Future<void> _saveNetworkSettings() async {
    setState(() {
      _savingNetwork = true;
    });
    try {
      final listenPort = int.tryParse(_listenPortController.text) ?? 6881;
      final maxGlobal = int.tryParse(_maxGlobalController.text) ?? 300;
      final maxPerTorrent = int.tryParse(_maxPerTorrentController.text) ?? 80;
      final maxActive = int.tryParse(_maxActiveController.text) ?? 3;
      final down = int.tryParse(_downloadRateController.text) ?? 0;
      final up = int.tryParse(_uploadRateController.text) ?? 0;

      await _settings.setListenPort(listenPort);
      await _settings.setMaxConnectionsGlobal(maxGlobal);
      await _settings.setMaxConnectionsPerTorrent(maxPerTorrent);
      await _settings.setMaxActiveDownloads(maxActive);
      await _settings.setDownloadRateLimitKib(down);
      await _settings.setUploadRateLimitKib(up);

      _listenPortController.text = '${_settings.listenPort}';
      _maxGlobalController.text = '${_settings.maxConnectionsGlobal}';
      _maxPerTorrentController.text = '${_settings.maxConnectionsPerTorrent}';
      _maxActiveController.text = '${_settings.maxActiveDownloads}';
      _downloadRateController.text = '${_settings.downloadRateLimitKib}';
      _uploadRateController.text = '${_settings.uploadRateLimitKib}';

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection settings saved')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _savingNetwork = false;
      });
    }
  }

  Future<void> _saveDownloadDestination() async {
    await _settings.setDownloadDestination(_downloadDirController.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Download folder saved')));
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    final appController = _maybeAppController();
    if (appController != null) {
      await appController.setThemeMode(mode);
    } else {
      await ThemeService.instance.setThemeMode(mode);
    }
    if (!mounted) return;
    setState(() {
      _themeMode = mode;
    });
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            _sectionCard(
              title: 'Downloads',
              children: [
                TextField(
                  controller: _downloadDirController,
                  decoration: const InputDecoration(
                    labelText: 'Default download folder',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _openDownloadFolder,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Browse'),
                    ),
                    if (Platform.isAndroid)
                      FilledButton.icon(
                        onPressed: () async {
                          if (_pickerBusy) return;
                          _pickerBusy = true;
                          try {
                            final result = await FilePicker.platform
                                .getDirectoryPath();
                            if (result != null) {
                              _downloadDirController.text = result;
                              await _settings.setDownloadDestination(result);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Download folder set: $result'),
                                ),
                              );
                              setState(() {});
                            }
                          } finally {
                            _pickerBusy = false;
                          }
                        },
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Choose download folder'),
                      ),
                    OutlinedButton(
                      onPressed: _saveDownloadDestination,
                      child: const Text('Save Folder'),
                    ),
                  ],
                ),
                SwitchListTile(
                  title: const Text('Auto-start when added'),
                  contentPadding: EdgeInsets.zero,
                  value: _settings.autoStartOnAdd,
                  onChanged: (v) async {
                    await _settings.setAutoStartOnAdd(v);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),

              ],
            ),
            const SizedBox(height: 10),
            _sectionCard(
              title: 'Connection',
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: _listenPortController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Listen port',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: _maxGlobalController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Max global connections',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: _maxPerTorrentController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Max connections per torrent',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: _maxActiveController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Max active downloads',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: _downloadRateController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText:
                              'Download rate limit (KiB/s, 0 = unlimited)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: _uploadRateController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Upload rate limit (KiB/s, 0 = unlimited)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  title: const Text('Enable DHT'),
                  contentPadding: EdgeInsets.zero,
                  value: _settings.useDht,
                  onChanged: (v) async {
                    await _settings.setUseDht(v);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
                SwitchListTile(
                  title: const Text('Enable Peer Exchange (PEX)'),
                  contentPadding: EdgeInsets.zero,
                  value: _settings.usePex,
                  onChanged: (v) async {
                    await _settings.setUsePex(v);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
                SwitchListTile(
                  title: const Text('Enable Local Peer Discovery (LPD)'),
                  contentPadding: EdgeInsets.zero,
                  value: _settings.useLpd,
                  onChanged: (v) async {
                    await _settings.setUseLpd(v);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: _savingNetwork ? null : _saveNetworkSettings,
                    child: Text(
                      _savingNetwork ? 'Saving...' : 'Save Connection Settings',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!_androidTorrentOnly)
              _sectionCard(
                title: 'AI',
                children: [
                  SwitchListTile(
                    title: const Text('Enable AI Copilot'),
                    contentPadding: EdgeInsets.zero,
                    value: _settings.enableAiCopilot,
                    onChanged: (v) async {
                      await _settings.setEnableAiCopilot(v);
                      if (!mounted) return;
                      setState(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Enable smart suggestions'),
                    contentPadding: EdgeInsets.zero,
                    value: _settings.enableSmartSuggestions,
                    onChanged: (v) async {
                      await _settings.setEnableSmartSuggestions(v);
                      if (!mounted) return;
                      setState(() {});
                    },
                  ),
                  TextField(
                    controller: _ollamaUrlController,
                    onChanged: (_) => _onUrlChanged(),
                    decoration: InputDecoration(
                      labelText: 'Ollama Host URL',
                      hintText: _settings.aiOllamaUrl,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context).dividerColor,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Recommended model: $kDefaultAiModel\n'
                                'Detected local models: ${_availableModels.length}',
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _availableModels.contains(_selectedModel)
                                  ? _selectedModel
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'Model to use',
                                border: OutlineInputBorder(),
                              ),
                              items: _availableModels
                                  .map(
                                    (m) => DropdownMenuItem<String>(
                                      value: m,
                                      child: Text(m),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _availableModels.isEmpty
                                  ? null
                                  : (value) {
                                      if (value == null) return;
                                      setState(() {
                                        _selectedModel = value;
                                      });
                                    },
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _modelStatus,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: _modelStatus.contains('Failed')
                                        ? Theme.of(context).colorScheme.error
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _loadingModels
                            ? null
                            : _fetchAvailableModels,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh available models',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: _downloadingRecommended
                          ? null
                          : _downloadRecommendedModel,
                      icon: const Icon(Icons.download_for_offline_outlined),
                      label: Text(
                        _downloadingRecommended
                            ? 'Downloading recommended model...'
                            : 'Download Recommended Model',
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: _saveAiSettings,
                      child: const Text('Save AI Settings'),
                    ),
                  ),
                ],
              ),
            if (!_androidTorrentOnly) const SizedBox(height: 10),
            _sectionCard(
              title: 'Interface',
              children: [
                DropdownButtonFormField<ThemeMode>(
                  value: _themeMode,
                  decoration: const InputDecoration(
                    labelText: 'Theme',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text('System'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text('Light'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text('Dark'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _setThemeMode(value);
                  },
                ),
                SwitchListTile(
                  title: const Text('Enable sound effects'),
                  contentPadding: EdgeInsets.zero,
                  value: _settings.soundEffectsEnabled,
                  onChanged: (v) async {
                    await _settings.setSoundEffectsEnabled(v);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
                if (!_androidTorrentOnly)
                  SwitchListTile(
                    title: const Text('Use persistent sidebar'),
                    contentPadding: EdgeInsets.zero,
                    value: _settings.usePersistentSidebar,
                    onChanged: (v) async {
                      await _settings.setUsePersistentSidebar(v);
                      if (!mounted) return;
                      setState(() {});
                    },
                  ),
                if (!_androidTorrentOnly)
                  SwitchListTile(
                    title: const Text('Use compact torrent rows'),
                    contentPadding: EdgeInsets.zero,
                    value: _settings.compactTorrentRows,
                    onChanged: (v) async {
                      await _settings.setCompactTorrentRows(v);
                      if (!mounted) return;
                      setState(() {});
                    },
                  ),
                if (!_androidTorrentOnly)
                  SwitchListTile(
                    title: const Text('Confirm before exiting app'),
                    contentPadding: EdgeInsets.zero,
                    value: _settings.confirmOnExit,
                    onChanged: (v) async {
                      await _settings.setConfirmOnExit(v);
                      if (!mounted) return;
                      setState(() {});
                    },
                  ),
                if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await toggleDesktopFullScreen();
                      },
                      icon: const Icon(Icons.fullscreen),
                      label: const Text('Toggle Fullscreen'),
                    ),
                  ),
                if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                  SwitchListTile(
                    title: const Text('Use system tray'),
                    contentPadding: EdgeInsets.zero,
                    value: _settings.useSystemTray,
                    onChanged: (v) async {
                      await _settings.setUseSystemTray(v);
                      if (!mounted) return;
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            v
                                ? 'System tray will be enabled when you restart the app'
                                : 'System tray will be disabled when you restart the app',
                          ),
                        ),
                      );
                    },
                  ),
                if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                  SwitchListTile(
                    title: const Text('Minimize to tray on close'),
                    contentPadding: EdgeInsets.zero,
                    value: _settings.minimizeToTrayOnClose,
                    onChanged: (v) async {
                      await _settings.setMinimizeToTrayOnClose(v);
                      if (!mounted) return;
                      setState(() {});
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _sectionCard(
              title: 'About and Diagnostics',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline),
                  title: const Text('Vault The Spire'),
                  subtitle: Text(
                    _androidTorrentOnly
                        ? 'Torrent manager for Android'
                        : 'Torrent manager with built-in AI copilot',
                  ),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.calendar_month),
                  title: Text('App version'),
                  subtitle: const Text('4.3.5'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.security),
                  title: const Text('Privacy policy'),
                  subtitle: Text(kPrivacyPolicyUrl),
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final now = DateTime.now().toIso8601String();
                        await _settings.setLastDiagnosticsExport(now);
                        if (!mounted) return;
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Diagnostics metadata updated'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.bug_report_outlined),
                      label: const Text('Mark Diagnostics Export'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () async {
                        await _settings.clearBrowserHistory();
                        if (!mounted) return;
                        setState(() {});
                      },
                      child: const Text('Clear Browser History'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _settings.lastDiagnosticsExport.isEmpty
                      ? 'Last diagnostics export: never'
                      : 'Last diagnostics export: ${_settings.lastDiagnosticsExport}',
                ),
                const SizedBox(height: 10),
                const Text(
                  'Data Safety:\n'
                  '- No personal data collection\n'
                  '- No location data\n'
                  '- No identifiers shared\n'
                  '- No advertising or analytics',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}