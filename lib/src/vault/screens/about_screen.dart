import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:convert_the_spire_reborn/src/vault/constants.dart';
import 'package:convert_the_spire_reborn/src/vault/services/ai_copilot_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/settings_service.dart';
import 'package:convert_the_spire_reborn/src/services/network_proxy_service.dart';
import 'package:convert_the_spire_reborn/src/widgets/tv_file_browser.dart';
import 'package:convert_the_spire_reborn/src/services/review_service.dart';

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
  late final TextEditingController _seedingRatioController;
  late final TextEditingController _proxyHostController;
  late final TextEditingController _proxyPortController;
  late final TextEditingController _proxyUsernameController;
  late final TextEditingController _proxyPasswordController;
  late AiCopilotService _aiService;

  List<String> _availableModels = <String>[];
  String? _selectedModel;
  bool _loadingModels = false;
  bool _downloadingRecommended = false;
  String _modelStatus = '';
  bool _savingNetwork = false;
  bool _pickerBusy = false;
  String _appVersionLabel = 'Loading...';
  bool _proxyEnabled = false;
  bool _proxyForTrackers = true;
  bool _proxyForPeers = true;

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
    _seedingRatioController = TextEditingController(
      text: _settings.maxSeedingRatio.toStringAsFixed(2),
    );
    _proxyHostController = TextEditingController();
    _proxyPortController = TextEditingController(text: '1080');
    _proxyUsernameController = TextEditingController();
    _proxyPasswordController = TextEditingController();
    _selectedModel = _settings.aiDefaultModel;
    if (!_androidTorrentOnly) {
      _aiService = AiCopilotService(baseUrl: _settings.aiOllamaUrl);
      _fetchAvailableModels();
    }
    unawaited(_loadProxySettings());
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersionLabel = '${info.version} (${info.buildNumber})';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _appVersionLabel = 'Unknown';
      });
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
    _seedingRatioController.dispose();
    _proxyHostController.dispose();
    _proxyPortController.dispose();
    _proxyUsernameController.dispose();
    _proxyPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadProxySettings() async {
    final proxy = await NetworkProxyService.load();
    if (!mounted) return;
    setState(() {
      _proxyEnabled = proxy.enabled;
      _proxyForTrackers = proxy.useForTrackers;
      _proxyForPeers = proxy.useForPeers;
      _proxyHostController.text = proxy.host;
      _proxyPortController.text = '${proxy.port}';
      _proxyUsernameController.text = proxy.username;
      _proxyPasswordController.text = proxy.password;
    });
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
        final seedingRatio =
          double.tryParse(_seedingRatioController.text.trim()) ?? 1.5;
      final proxyPort = int.tryParse(_proxyPortController.text) ?? 1080;

      await Future.wait([
        _settings.setListenPort(listenPort),
        _settings.setMaxConnectionsGlobal(maxGlobal),
        _settings.setMaxConnectionsPerTorrent(maxPerTorrent),
        _settings.setMaxActiveDownloads(maxActive),
        _settings.setDownloadRateLimitKib(down),
        _settings.setUploadRateLimitKib(up),
        _settings.setMaxSeedingRatio(seedingRatio),
        NetworkProxyService.save(
          ProxySettings(
            enabled: _proxyEnabled,
            host: _proxyHostController.text.trim(),
            port: proxyPort,
            username: _proxyUsernameController.text.trim(),
            password: _proxyPasswordController.text,
            useForTrackers: _proxyForTrackers,
            useForPeers: _proxyForPeers,
          ),
        ),
      ]);

      _listenPortController.text = '${_settings.listenPort}';
      _maxGlobalController.text = '${_settings.maxConnectionsGlobal}';
      _maxPerTorrentController.text = '${_settings.maxConnectionsPerTorrent}';
      _maxActiveController.text = '${_settings.maxActiveDownloads}';
      _downloadRateController.text = '${_settings.downloadRateLimitKib}';
      _uploadRateController.text = '${_settings.uploadRateLimitKib}';
        _seedingRatioController.text =
          _settings.maxSeedingRatio.toStringAsFixed(2);

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

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse(kPrivacyPolicyUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open privacy policy link.')),
      );
    }
  }

  Future<void> _exportDiagnostics() async {
    final now = DateTime.now();
    final safeTs = now.toIso8601String().replaceAll(':', '-');
    final fileName = 'vault_diagnostics_$safeTs.txt';
    String? path;

    if (!Platform.isAndroid && !Platform.isIOS) {
      path = await FilePicker.platform.saveFile(fileName: fileName);
    }

    if ((path == null || path.isEmpty) &&
        _settings.downloadDestination.isNotEmpty) {
      path =
          '${_settings.downloadDestination}${Platform.pathSeparator}$fileName';
    }

    if (path == null || path.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diagnostics export cancelled.')),
      );
      return;
    }

    final package = await PackageInfo.fromPlatform();
    final payload = <String, dynamic>{
      'appName': package.appName,
      'version': package.version,
      'buildNumber': package.buildNumber,
      'platform': defaultTargetPlatform.name,
      'generatedAt': now.toIso8601String(),
      'settings': <String, dynamic>{
        'downloadDestination': _settings.downloadDestination,
        'autoStartOnAdd': _settings.autoStartOnAdd,
        'useDht': _settings.useDht,
        'usePex': _settings.usePex,
        'useLpd': _settings.useLpd,
        'listenPort': _settings.listenPort,
        'maxConnectionsGlobal': _settings.maxConnectionsGlobal,
        'maxConnectionsPerTorrent': _settings.maxConnectionsPerTorrent,
        'maxActiveDownloads': _settings.maxActiveDownloads,
        'downloadRateLimitKib': _settings.downloadRateLimitKib,
        'uploadRateLimitKib': _settings.uploadRateLimitKib,
        'allowSeedingAfterComplete': _settings.allowSeedingAfterComplete,
        'maxSeedingRatio': _settings.maxSeedingRatio,
        'enableAiCopilot': _settings.enableAiCopilot,
        'aiDefaultModel': _settings.aiDefaultModel,
      },
    };

    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );

    await _settings.setLastDiagnosticsExport(now.toIso8601String());
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Diagnostics exported: $path')),
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: cs.onSurface,
              ),
            ),
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
    final width = MediaQuery.of(context).size.width;
    final maxContentWidth = width > 1700 ? 1280.0 : 1120.0;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                width > 1200 ? 24 : 16, 16, width > 1200 ? 24 : 16, 16),
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
                                final result = await pickDirectoryPath(
                                  context,
                                  dialogTitle: 'Select download folder',
                                );
                                if (result != null) {
                                  _downloadDirController.text = result;
                                  await _settings
                                      .setDownloadDestination(result);
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content:
                                          Text('Download folder set: $result'),
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
                              labelText:
                                  'Upload rate limit (KiB/s, 0 = unlimited)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 260,
                          child: TextField(
                            controller: _seedingRatioController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                              labelText:
                                  'Seeding ratio cap (e.g. 1.50, 0 = unlimited)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      title: const Text('Allow seeding after completion'),
                      subtitle: const Text(
                        'Disable to auto-pause torrents as soon as download completes.',
                      ),
                      contentPadding: EdgeInsets.zero,
                      value: _settings.allowSeedingAfterComplete,
                      onChanged: (v) async {
                        await _settings.setAllowSeedingAfterComplete(v);
                        if (!mounted) return;
                        setState(() {});
                      },
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
                    const Divider(height: 20),
                    SwitchListTile(
                      title: const Text('Enable proxy'),
                      contentPadding: EdgeInsets.zero,
                      value: _proxyEnabled,
                      onChanged: (v) => setState(() => _proxyEnabled = v),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: _proxyHostController,
                            decoration: const InputDecoration(
                              labelText: 'Proxy host',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 140,
                          child: TextField(
                            controller: _proxyPortController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Proxy port',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: _proxyUsernameController,
                            decoration: const InputDecoration(
                              labelText: 'Proxy username',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: _proxyPasswordController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Proxy password',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      title: const Text('Use proxy for trackers'),
                      contentPadding: EdgeInsets.zero,
                      value: _proxyForTrackers,
                      onChanged: (v) => setState(() => _proxyForTrackers = v),
                    ),
                    SwitchListTile(
                      title: const Text('Use proxy for peers'),
                      contentPadding: EdgeInsets.zero,
                      value: _proxyForPeers,
                      onChanged: (v) => setState(() => _proxyForPeers = v),
                    ),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              final ok = await NetworkProxyService
                                  .testSocks5Connection();
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok
                                        ? 'Proxy connection successful'
                                        : 'Proxy test failed',
                                  ),
                                ),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Proxy test failed: $e')),
                              );
                            }
                          },
                          icon: const Icon(Icons.network_check),
                          label: const Text('Test proxy'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'SOCKS5 proxy settings are shared by torrent tasks and yt-dlp downloads.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        onPressed: _savingNetwork ? null : _saveNetworkSettings,
                        child: Text(
                          _savingNetwork
                              ? 'Saving...'
                              : 'Save Connection Settings',
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
                                  initialValue:
                                      _availableModels.contains(_selectedModel)
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: _modelStatus.contains('Failed')
                                            ? Theme.of(context)
                                                .colorScheme
                                                .error
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
                            onPressed:
                                _loadingModels ? null : _fetchAvailableModels,
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
                  title: 'General Settings',
                  children: [
                    const Text(
                      'General app settings are centralized in the main app Settings tab. '
                      'This screen now contains torrent-specific configuration only.',
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
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.calendar_month),
                      title: const Text('App version'),
                      subtitle: Text(_appVersionLabel),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.security),
                      title: const Text('Privacy policy'),
                      subtitle: Text(kPrivacyPolicyUrl),
                      onTap: _openPrivacyPolicy,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.star_rate_outlined),
                      title: const Text('Rate Convert The Spire Reborn'),
                      subtitle: const Text('Leave a rating on the Play Store'),
                      onTap: () async {
                        await ReviewService.openStoreListing();
                      },
                    ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final narrow = constraints.maxWidth < 640;
                        final actions = <Widget>[
                          OutlinedButton.icon(
                            onPressed: _exportDiagnostics,
                            icon: const Icon(Icons.bug_report_outlined),
                            label: const Text('Export Diagnostics'),
                          ),
                          OutlinedButton(
                            onPressed: () async {
                              await _settings.clearBrowserHistory();
                              if (!mounted) return;
                              setState(() {});
                            },
                            child: const Text('Clear Browser History'),
                          ),
                        ];

                        if (narrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              actions[0],
                              const SizedBox(height: 8),
                              actions[1],
                            ],
                          );
                        }

                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: actions,
                        );
                      },
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
        ),
      ),
    );
  }
}
