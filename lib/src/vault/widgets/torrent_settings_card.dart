import 'dart:async';

import 'package:convert_the_spire_reborn/src/services/network_proxy_service.dart';
import 'package:convert_the_spire_reborn/src/utils/l10n.dart';
import 'package:convert_the_spire_reborn/src/vault/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The torrent settings, as one card in the app's Settings screen.
///
/// They used to be a Settings tab of their own inside the Torrents section.
/// The torrent folder is set with the other download folders.
class TorrentSettingsCard extends StatefulWidget {
  const TorrentSettingsCard({super.key});

  @override
  State<TorrentSettingsCard> createState() => _TorrentSettingsCardState();
}

class _TorrentSettingsCardState extends State<TorrentSettingsCard> {
  final SettingsService _settings = SettingsService.instance;
  late final TextEditingController _listenPort;
  late final TextEditingController _maxGlobal;
  late final TextEditingController _maxPerTorrent;
  late final TextEditingController _maxActive;
  late final TextEditingController _downloadRate;
  late final TextEditingController _uploadRate;
  late final TextEditingController _seedingRatio;
  final _proxyHost = TextEditingController();
  final _proxyPort = TextEditingController(text: '1080');
  final _proxyUsername = TextEditingController();
  final _proxyPassword = TextEditingController();
  bool _proxyEnabled = false;
  bool _proxyForTrackers = true;
  bool _proxyForPeers = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _listenPort = TextEditingController();
    _maxGlobal = TextEditingController();
    _maxPerTorrent = TextEditingController();
    _maxActive = TextEditingController();
    _downloadRate = TextEditingController();
    _uploadRate = TextEditingController();
    _seedingRatio = TextEditingController();
    _showSavedNumbers();
    unawaited(_loadProxy());
  }

  @override
  void dispose() {
    for (final c in [
      _listenPort,
      _maxGlobal,
      _maxPerTorrent,
      _maxActive,
      _downloadRate,
      _uploadRate,
      _seedingRatio,
      _proxyHost,
      _proxyPort,
      _proxyUsername,
      _proxyPassword,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _showSavedNumbers() {
    _listenPort.text = '${_settings.listenPort}';
    _maxGlobal.text = '${_settings.maxConnectionsGlobal}';
    _maxPerTorrent.text = '${_settings.maxConnectionsPerTorrent}';
    _maxActive.text = '${_settings.maxActiveDownloads}';
    _downloadRate.text = '${_settings.downloadRateLimitKib}';
    _uploadRate.text = '${_settings.uploadRateLimitKib}';
    _seedingRatio.text = _settings.maxSeedingRatio.toStringAsFixed(2);
  }

  Future<void> _loadProxy() async {
    final proxy = await NetworkProxyService.load();
    if (!mounted) return;
    setState(() {
      _proxyEnabled = proxy.enabled;
      _proxyForTrackers = proxy.useForTrackers;
      _proxyForPeers = proxy.useForPeers;
      _proxyHost.text = proxy.host;
      _proxyPort.text = '${proxy.port}';
      _proxyUsername.text = proxy.username;
      _proxyPassword.text = proxy.password;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Future.wait([
        _settings.setListenPort(int.tryParse(_listenPort.text) ?? 6881),
        _settings.setMaxConnectionsGlobal(int.tryParse(_maxGlobal.text) ?? 300),
        _settings.setMaxConnectionsPerTorrent(
            int.tryParse(_maxPerTorrent.text) ?? 80),
        _settings.setMaxActiveDownloads(int.tryParse(_maxActive.text) ?? 3),
        _settings.setDownloadRateLimitKib(int.tryParse(_downloadRate.text) ?? 0),
        _settings.setUploadRateLimitKib(int.tryParse(_uploadRate.text) ?? 0),
        _settings.setMaxSeedingRatio(
            double.tryParse(_seedingRatio.text.trim()) ?? 1.5),
        NetworkProxyService.save(
          ProxySettings(
            enabled: _proxyEnabled,
            host: _proxyHost.text.trim(),
            port: int.tryParse(_proxyPort.text) ?? 1080,
            username: _proxyUsername.text.trim(),
            password: _proxyPassword.text,
            useForTrackers: _proxyForTrackers,
            useForPeers: _proxyForPeers,
          ),
        ),
      ]);
      // Out-of-range values come back clamped.
      _showSavedNumbers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.connectionSettingsSaved)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testProxy() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    String message;
    try {
      final ok = await NetworkProxyService.testSocks5Connection();
      message = ok ? l10n.proxyConnectionSuccessful : l10n.proxyTestFailed;
    } catch (e) {
      message = l10n.proxyTestFailed2(e);
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _number(TextEditingController controller, String label,
      {bool decimal = false}) {
    return SizedBox(
      width: 220,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          if (decimal)
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
          else
            FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _toggle(String title, bool value, Future<void> Function(bool) save,
      {String? subtitle}) {
    return SwitchListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: (v) async {
        await save(v);
        if (mounted) setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.swap_vert),
                const SizedBox(width: 8),
                Text(l10n.tabTorrents,
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const Divider(),
            _toggle(l10n.autoStartWhenAdded, _settings.autoStartOnAdd,
                _settings.setAutoStartOnAdd),
            _toggle(
              l10n.allowSeedingAfterCompletion,
              _settings.allowSeedingAfterComplete,
              _settings.setAllowSeedingAfterComplete,
              subtitle: l10n.disableAutoPauseTorrentsSoon,
            ),
            _toggle(l10n.enableDht, _settings.useDht, _settings.setUseDht),
            _toggle(l10n.enablePeerExchangePex, _settings.usePex,
                _settings.setUsePex),
            _toggle(l10n.enableLocalPeerDiscoveryLpd, _settings.useLpd,
                _settings.setUseLpd),
            const SizedBox(height: 12),
            Text(l10n.connection, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _number(_listenPort, l10n.listenPort),
                _number(_maxGlobal, l10n.maxGlobalConnections),
                _number(_maxPerTorrent, l10n.maxConnectionsPerTorrent),
                _number(_maxActive, l10n.maxActiveDownloads),
                _number(_downloadRate, l10n.downloadRateLimitKibS),
                _number(_uploadRate, l10n.uploadRateLimitKibS),
                _number(_seedingRatio, l10n.seedingRatioCapEG, decimal: true),
              ],
            ),
            const Divider(height: 28),
            SwitchListTile(
              title: Text(l10n.enableProxy),
              subtitle: Text(l10n.socks5ProxySettingsSharedBy),
              contentPadding: EdgeInsets.zero,
              value: _proxyEnabled,
              onChanged: (v) => setState(() => _proxyEnabled = v),
            ),
            if (_proxyEnabled) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _proxyHost,
                      decoration: InputDecoration(
                        labelText: l10n.proxyHost,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  _number(_proxyPort, l10n.proxyPort),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _proxyUsername,
                      decoration: InputDecoration(
                        labelText: l10n.proxyUsername,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _proxyPassword,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: l10n.proxyPassword,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                title: Text(l10n.useProxyTrackers),
                contentPadding: EdgeInsets.zero,
                value: _proxyForTrackers,
                onChanged: (v) => setState(() => _proxyForTrackers = v),
              ),
              SwitchListTile(
                title: Text(l10n.useProxyPeers),
                contentPadding: EdgeInsets.zero,
                value: _proxyForPeers,
                onChanged: (v) => setState(() => _proxyForPeers = v),
              ),
              OutlinedButton.icon(
                onPressed: _testProxy,
                icon: const Icon(Icons.network_check),
                label: Text(l10n.testProxy),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving ? l10n.saving : l10n.saveConnectionSettings,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
