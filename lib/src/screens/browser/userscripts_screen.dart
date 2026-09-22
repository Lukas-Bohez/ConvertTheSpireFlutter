import 'package:flutter/material.dart';

import '../../browser/userscripts/userscript.dart';
import '../../browser/userscripts/userscript_service.dart';
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
        title: const Text('Install from URL'),
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
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty) return;

    setState(() => _busy = true);
    final error = await widget.service.installFromUrl(url.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    Snack.show(context, error ?? 'Script installed',
        level: error == null ? SnackLevel.success : SnackLevel.error);
  }

  Future<void> _installFromPaste() async {
    final controller = TextEditingController();
    final source = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste a script'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 14,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              hintText: '// ==UserScript==\n// @name  My script\n…',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Install'),
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
          ? 'That is not a userscript — it needs a // ==UserScript== header.'
          : 'Installed "${installed.name}"',
      level: installed == null ? SnackLevel.error : SnackLevel.success,
    );
  }

  Future<void> _confirmRemove(UserScript script) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove "${script.name}"?'),
        content: const Text('The script will be deleted from this device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
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
        title: const Text('Userscripts'),
        actions: [
          IconButton(
            tooltip: 'Update all',
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    final n = await service.updateAll();
                    if (!mounted) return;
                    setState(() => _busy = false);
                    Snack.show(context,
                        n == 0 ? 'Nothing to update' : 'Updated $n script(s)',
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
            title: const Text('Run userscripts'),
            subtitle: Text(scripts.isEmpty
                ? 'Nothing installed yet'
                : '${service.enabledCount} of ${scripts.length} switched on'),
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
                                  ? 'No sites configured — this will never run'
                                  : targets.take(2).join(', ') +
                                      (targets.length > 2
                                          ? ' +${targets.length - 2} more'
                                          : ''),
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        secondary: IconButton(
                          tooltip: 'Remove',
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
        label: const Text('Add script'),
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
              title: const Text('Install from URL'),
              subtitle: const Text('Paste a link to a .user.js file'),
              onTap: () {
                Navigator.pop(ctx);
                _installFromUrl();
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('Paste the script'),
              subtitle: const Text('Copy the code straight in'),
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
            Text('No userscripts yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Userscripts change how websites look and behave. Most scripts '
              'written for Tampermonkey or Greasemonkey work here unchanged — '
              'find them on sites like Greasy Fork and install by URL.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
