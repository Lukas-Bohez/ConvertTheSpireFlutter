import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/foreground_service.dart';
import '../services/watch_party/watch_party_service.dart';
import '../utils/l10n.dart';
import '../utils/snack.dart';
import 'player.dart' show PlayerState;

/// Watch Together: host a room or join one with a code.
///
/// Kept deliberately small — two buttons and a code — because the common case
/// is someone reading a code off a TV to a friend on the phone.
class WatchPartySheet extends StatefulWidget {
  const WatchPartySheet({super.key});

  /// Opens the sheet.
  ///
  /// [PlayerState] is re-provided explicitly so the sheet works no matter
  /// which navigator it is pushed on. Providers now live above MaterialApp,
  /// but a sheet that reaches for app state and finds none renders as a grey
  /// error screen in release builds, so this stays belt and braces (issue #7).
  static Future<void> show(BuildContext context) {
    final player = context.read<PlayerState>();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ChangeNotifierProvider<PlayerState>.value(
        value: player,
        child: const WatchPartySheet(),
      ),
    );
  }

  @override
  State<WatchPartySheet> createState() => _WatchPartySheetState();
}

class _WatchPartySheetState extends State<WatchPartySheet> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_fillDefaultName());
  }

  /// Defaults the display name to the device's own name.
  ///
  /// Everybody in a room used to show up as "Me", which is useless when the
  /// point is telling devices apart (issue #7).
  Future<void> _fillDefaultName() async {
    final name = await ForegroundService.deviceName() ?? _fallbackDeviceName();
    if (!mounted || _nameController.text.isNotEmpty) return;
    _nameController.text = name;
  }

  String _fallbackDeviceName() {
    try {
      final host = Platform.localHostname.trim();
      if (host.isNotEmpty && host.toLowerCase() != 'localhost') return host;
    } catch (e) {
      debugPrint('watch party: host name unavailable: $e');
    }
    return context.l10n.device2;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _host() async {
    final player = context.read<PlayerState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await player.startWatchParty(displayName: _nameController.text.trim());
    } catch (e) {
      setState(() => _error = context.l10n.couldNotStartRoom(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final player = context.read<PlayerState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await player.joinWatchParty(_codeController.text,
        displayName: _nameController.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  Future<void> _leave() async {
    await context.read<PlayerState>().leaveWatchParty();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerState>();
    final status = player.watchParty.status;
    final theme = Theme.of(context);

    // Scrollable so the sheet still fits with the keyboard up on a small
    // phone, or on a phone held sideways.
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 4, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.groups_rounded),
                const SizedBox(width: 10),
                Text(context.l10n.watchTogether2, style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.everyoneSameWifiStaysStep,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            if (status.isActive)
              _ActiveRoom(status: status, onLeave: _busy ? null : _leave)
            else
              _JoinOrHost(
                nameController: _nameController,
                codeController: _codeController,
                busy: _busy,
                onHost: _host,
                onJoin: _join,
              ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_error!,
                          style: TextStyle(
                              color: theme.colorScheme.onErrorContainer)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _JoinOrHost extends StatelessWidget {
  const _JoinOrHost({
    required this.nameController,
    required this.codeController,
    required this.busy,
    required this.onHost,
    required this.onJoin,
  });

  final TextEditingController nameController;
  final TextEditingController codeController;
  final bool busy;
  final VoidCallback onHost;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: nameController,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: context.l10n.name,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : onHost,
          icon: const Icon(Icons.play_circle_outline),
          label: Text(context.l10n.startRoom),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(context.l10n.joinOne,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: codeController,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          maxLength: 8,
          onSubmitted: busy ? null : (_) => onJoin(),
          decoration: InputDecoration(
            labelText: context.l10n.roomCode,
            hintText: 'ABC234',
            border: const OutlineInputBorder(),
            isDense: true,
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy ? null : onJoin,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.login_rounded),
          label: Text(busy ? context.l10n.lookingRoom : context.l10n.join),
        ),
      ],
    );
  }
}

class _ActiveRoom extends StatelessWidget {
  const _ActiveRoom({required this.status, required this.onLeave});

  final WatchPartyStatus status;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isHost = status.role == WatchPartyRole.host;
    final code = status.roomCode ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Text(
                isHost ? context.l10n.roomCode2 : context.l10n.room2,
                style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(height: 8),
              SelectableText(
                code,
                style: theme.textTheme.displaySmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6,
                ),
              ),
              if (isHost) ...[
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (context.mounted) {
                      Snack.show(context, context.l10n.roomCodeCopied,
                          level: SnackLevel.success);
                    }
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(context.l10n.copyCode),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(
              status.role == WatchPartyRole.connecting
                  ? Icons.wifi_tethering
                  : Icons.check_circle_rounded,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(status.message)),
          ],
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: onLeave,
          icon: const Icon(Icons.logout_rounded),
          label: Text(isHost ? context.l10n.closeRoom : context.l10n.leaveRoom),
        ),
      ],
    );
  }
}
