import 'package:flutter/material.dart';

import '../../browser/userscripts/userscript.dart';
import '../../browser/userscripts/userscript_service.dart';
import '../../utils/l10n.dart';
import '../../utils/snack.dart';

/// Install and manage userscripts (Tampermonkey-compatible).
class UserScriptsScreen extends StatefulWidget {
  const UserScriptsScreen({super.key, required this.service});

  final UserScriptService service;

  @override
  State<UserScriptsScreen> createState() => _UserScriptsScreenState();
}

class _UserScriptsScreenState extends State<UserScriptsScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _installFromUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.installFromUrl),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://…/script.user.js',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(context.l10n.actionCancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(context.l10n.install),
          ),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty) return;

    setState(() => _busy = true);
    final error = await widget.service.installFromUrl(url.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    Snack.show(context, error ?? context.l10n.scriptInstalled,
        level: error == null ? SnackLevel.success : SnackLevel.error);
  }

  Future<void> _installFromPaste() async {
    final controller = TextEditingController();
    final source = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.pasteScript),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 14,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(
              hintText: context.l10n.userscriptNameMyScript,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(context.l10n.actionCancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(context.l10n.install),
          ),
        ],
      ),
    );
    if (source == null || source.trim().isEmpty) return;

    final installed = await widget.service.installFromSource(source);
    if (!mounted) return;
    Snack.show(
      context,
      installed == null
          ? context.l10n.notUserscriptNeedsUserscriptHeader
          : context.l10n.installed3(installed.name),
      level: installed == null ? SnackLevel.error : SnackLevel.success,
    );
  }

  Future<void> _confirmRemove(UserScript script) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.remove2(script.name)),
        content: Text(context.l10n.scriptWillDeletedFromDevice),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.actionCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.l10n.actionRemove)),
        ],
      ),
    );
    if (ok == true) await widget.service.remove(script.id);
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final scripts = service.scripts;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.userscripts),
        actions: [
          IconButton(
            tooltip: context.l10n.updateAll,
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    final n = await service.updateAll();
                    if (!mounted) return;
                    setState(() => _busy = false);
                    Snack.show(context,
                        n == 0 ? context.l10n.nothingUpdate : context.l10n.updatedScriptS(n),
                        level: SnackLevel.info);
                  },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          SwitchListTile(
            title: Text(context.l10n.runUserscripts),
            subtitle: Text(scripts.isEmpty
                ? context.l10n.nothingInstalledYet
                : context.l10n.switched(service.enabledCount, scripts.length)),
            value: service.enabled,
            onChanged: (v) => service.setEnabled(v),
          ),
          const Divider(height: 1),
          Expanded(
            child: scripts.isEmpty
                ? const _EmptyState()
                : ListView.separated(
                    itemCount: scripts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final script = scripts[i];
                      final targets = [...script.matches, ...script.includes];
                      return SwitchListTile(
                        value: script.enabled,
                        onChanged: (_) => service.toggleScript(script.id),
                        title: Text(script.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (script.description.isNotEmpty)
                              Text(script.description,
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                            Text(
                              targets.isEmpty
                                  ? context.l10n.noSitesConfiguredWillNever
                                  : targets.take(2).join(', ') +
                                      (targets.length > 2
                                          ? context.l10n.more4(targets.length - 2)
                                          : ''),
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        secondary: IconButton(
                          tooltip: context.l10n.actionRemove,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmRemove(script),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _showAddSheet,
        icon: const Icon(Icons.add),
        label: Text(context.l10n.addScript),
      ),
    );
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(context.l10n.installFromUrl),
              subtitle: Text(context.l10n.pasteLinkUserJsFile),
              onTap: () {
                Navigator.pop(ctx);
                _installFromUrl();
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: Text(context.l10n.pasteScript2),
              subtitle: Text(context.l10n.copyCodeStraight),
              onTap: () {
                Navigator.pop(ctx);
                _installFromPaste();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.extension_outlined, size: 48),
            const SizedBox(height: 16),
            Text(context.l10n.noUserscriptsYet,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              context.l10n.userscriptsChangeHowWebsitesLook,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
