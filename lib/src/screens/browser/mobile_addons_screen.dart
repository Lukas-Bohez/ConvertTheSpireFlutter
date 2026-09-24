import 'package:flutter/material.dart';

import '../../browser/adblock/adblock_service.dart';
import '../../browser/userscripts/userscript_service.dart';
import 'userscripts_screen.dart';

/// Extensions, for a browser engine that cannot run them.
///
/// Android's System WebView (and the engine on macOS before 15.4) has no
/// extension host, so Chrome and Firefox extensions cannot load there; the
/// Windows app runs them through WebView2. Phone users looked for an
/// Extensions entry, found none, and concluded the browser had nothing. This
/// screen says plainly what runs here instead: the built-in blocker, and
/// userscripts, which cover most of what people install extensions for, with
/// one tap to find popular ones.
///
/// Pops with a URL when the user picks something to open in the browser.
class MobileAddonsScreen extends StatefulWidget {
  const MobileAddonsScreen({
    super.key,
    required this.userScripts,
    required this.adBlock,
  });

  final UserScriptService userScripts;
  final AdBlockService adBlock;

  /// Greasy Fork's search, most-installed first.
  static String searchUrl(String query) =>
      Uri.https('greasyfork.org', '/scripts', {
        'q': query,
        'sort': 'total_installs',
      }).toString();

  /// Things people install extensions for, as userscript searches.
  static const List<AddonIdea> ideas = [
    AddonIdea(
      icon: Icons.dark_mode_outlined,
      title: 'Dark mode for every site',
      query: 'dark mode',
    ),
    AddonIdea(
      icon: Icons.thumb_down_alt_outlined,
      title: 'See YouTube dislikes again',
      query: 'Return YouTube Dislike',
    ),
    AddonIdea(
      icon: Icons.fast_forward_outlined,
      title: 'Skip sponsor segments on YouTube',
      query: 'SponsorBlock',
    ),
    AddonIdea(
      icon: Icons.tune,
      title: 'YouTube tweaks and cleanups',
      query: 'YouTube enhancer',
    ),
    AddonIdea(
      icon: Icons.translate,
      title: 'Translate pages',
      query: 'translate',
    ),
    AddonIdea(
      icon: Icons.forum_outlined,
      title: 'Cleaner Reddit',
      query: 'reddit',
    ),
  ];

  @override
  State<MobileAddonsScreen> createState() => _MobileAddonsScreenState();
}

/// One suggested kind of add-on.
class AddonIdea {
  const AddonIdea({
    required this.icon,
    required this.title,
    required this.query,
  });

  final IconData icon;
  final String title;
  final String query;
}

class _MobileAddonsScreenState extends State<MobileAddonsScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.userScripts.addListener(_changed);
    widget.adBlock.addListener(_changed);
  }

  @override
  void dispose() {
    widget.userScripts.removeListener(_changed);
    widget.adBlock.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _open(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    Navigator.of(context).pop(MobileAddonsScreen.searchUrl(q));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scripts = widget.userScripts.scripts;

    return Scaffold(
      appBar: AppBar(title: const Text('Extensions')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Card(
              color: theme.colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Chrome and Firefox extensions need a desktop browser '
                  'engine, and the web view on this device cannot load '
                  'them. What most people install extensions for works '
                  'here anyway: ad blocking is built in, and userscripts '
                  'add dark mode, YouTube tweaks and much more.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer),
                ),
              ),
            ),
          ),
          const _Heading('On this device'),
          SwitchListTile(
            secondary: const Icon(Icons.block),
            title: const Text('Ad and tracker blocking'),
            subtitle: const Text('Built in, nothing to install'),
            value: widget.adBlock.adBlockEnabled,
            onChanged: (v) => widget.adBlock.setEnabled(v),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Userscripts'),
            subtitle: Text(scripts.isEmpty
                ? 'Tampermonkey-compatible. None installed yet'
                : '${widget.userScripts.enabledCount} of ${scripts.length} '
                    'switched on'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => UserScriptsScreen(service: widget.userScripts),
            )),
          ),
          const _Heading('Find add-ons'),
          for (final idea in MobileAddonsScreen.ideas)
            ListTile(
              leading: Icon(idea.icon),
              title: Text(idea.title),
              trailing: const Icon(Icons.open_in_new, size: 20),
              onTap: () => _open(idea.query),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Search userscripts',
                hintText: 'A site or what you want to change',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _open(_search.text),
                ),
              ),
              onSubmitted: _open,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'These open Greasy Fork in the browser. On a script’s '
              'page, tap Install: the app shows where the script comes from '
              'and asks before installing it. A userscript can read and '
              'change the sites it runs on, so install only ones you trust.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const _Heading('Full extensions'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'The Windows app runs Chrome extensions and add-ons from '
              'addons.mozilla.org, such as uBlock Origin Lite and Dark '
              'Reader, with their buttons and settings pages.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall
            ?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}
