import 'package:flutter/material.dart';

import '../../browser/adblock/adblock_service.dart';
import '../../browser/userscripts/userscript_service.dart';
import '../../utils/l10n.dart';
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

  /// Things people install extensions for, as userscript searches. The
  /// searches stay in English: that is the language most scripts are
  /// described in.
  static List<AddonIdea> ideas(AppLocalizations l) => [
        AddonIdea(
          icon: Icons.dark_mode_outlined,
          title: l.addonDarkMode,
          query: 'dark mode',
        ),
        AddonIdea(
          icon: Icons.thumb_down_alt_outlined,
          title: l.addonYoutubeDislikes,
          query: 'Return YouTube Dislike',
        ),
        AddonIdea(
          icon: Icons.fast_forward_outlined,
          title: l.addonSponsorBlock,
          query: 'SponsorBlock',
        ),
        AddonIdea(
          icon: Icons.tune,
          title: l.addonYoutubeTweaks,
          query: 'YouTube enhancer',
        ),
        AddonIdea(
          icon: Icons.translate,
          title: l.addonTranslate,
          query: 'translate',
        ),
        AddonIdea(
          icon: Icons.forum_outlined,
          title: l.addonReddit,
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
      appBar: AppBar(title: Text(context.l10n.extensions)),
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
                  context.l10n.chromeFirefoxExtensionsNeedDesktop,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer),
                ),
              ),
            ),
          ),
          _Heading(context.l10n.device),
          SwitchListTile(
            secondary: const Icon(Icons.block),
            title: Text(context.l10n.adTrackerBlocking),
            subtitle: Text(context.l10n.builtNothingInstall),
            value: widget.adBlock.adBlockEnabled,
            onChanged: (v) => widget.adBlock.setEnabled(v),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(context.l10n.userscripts),
            subtitle: Text(scripts.isEmpty
                ? context.l10n.tampermonkeyCompatibleNoneInstalledYet
                : context.l10n.switched(widget.userScripts.enabledCount, scripts.length)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => UserScriptsScreen(service: widget.userScripts),
            )),
          ),
          _Heading(context.l10n.findAddOns),
          for (final idea in MobileAddonsScreen.ideas(context.l10n))
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
                labelText: context.l10n.searchUserscripts,
                hintText: context.l10n.siteWhatWantChange,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: context.l10n.tabSearch,
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
              context.l10n.theseOpenGreasyForkBrowser,
              style: theme.textTheme.bodySmall,
            ),
          ),
          _Heading(context.l10n.fullExtensions),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              context.l10n.windowsAppRunsChromeExtensions,
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
