import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
// import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/about_screen.dart';
import 'screens/ai_chat_screen.dart';
import 'screens/browser_screen.dart';
import 'screens/guide_screen.dart';
import 'screens/torrentspire_ai_screen.dart';
import 'screens/torrents_screen.dart';
import 'widgets/platform_adaptive_scaffold.dart';

final bool _androidTorrentOnly =
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

final appRouter = GoRouter(
  initialLocation: _androidTorrentOnly ? '/torrents' : '/copilot',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/copilot',
          builder: (_, __) => _androidTorrentOnly
              ? const TorrentsScreen()
              : const TorrentSpireAiScreen(),
        ),
        GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
        GoRoute(path: '/about', builder: (_, __) => const AboutScreen()),
        GoRoute(path: '/browser', builder: (_, __) => const BrowserScreen()),
        GoRoute(path: '/guide', builder: (_, __) => const GuideScreen()),
        GoRoute(
          path: '/ai_chat',
          builder: (_, __) =>
              _androidTorrentOnly ? const TorrentsScreen() : const AiChatScreen(),
        ),
        GoRoute(path: '/torrents', builder: (_, __) => const TorrentsScreen()),
      ],
    ),
  ],
);
