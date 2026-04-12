enum TorrentIntentType {
  search,
  downloadTop,
  whatsDownloading,
  safetyCheck,
  betterVersion,
  diskSpace,
  none,
}

class TorrentIntent {
  final TorrentIntentType type;
  final String payload;

  const TorrentIntent(this.type, {this.payload = ''});
}

class IntentParser {
  static const List<String> _keywordGatePhrases = <String>[
    'search for',
    'download',
    'find me',
    "what's downloading",
    'what is downloading',
    'how much space',
  ];

  bool passesKeywordGate(String message) {
    final lower = message.toLowerCase();
    return _keywordGatePhrases.any(lower.contains);
  }

  TorrentIntent parse(String message) {
    final text = message.trim();
    final lower = text.toLowerCase();

    if (lower.startsWith('search for ')) {
      return TorrentIntent(
        TorrentIntentType.search,
        payload: text.substring('search for '.length).trim(),
      );
    }

    if (lower.contains('download the top result')) {
      return const TorrentIntent(TorrentIntentType.downloadTop);
    }

    if (lower.contains("what's downloading") ||
        lower.contains('what is downloading')) {
      return const TorrentIntent(TorrentIntentType.whatsDownloading);
    }

    if (lower.startsWith('is ') && lower.endsWith(' safe?')) {
      final name = text.substring(3, text.length - 6).trim();
      return TorrentIntent(TorrentIntentType.safetyCheck, payload: name);
    }

    if (lower.contains('better version')) {
      return const TorrentIntent(TorrentIntentType.betterVersion);
    }

    if (lower.contains('space do i have left')) {
      return const TorrentIntent(TorrentIntentType.diskSpace);
    }

    return const TorrentIntent(TorrentIntentType.none);
  }
}
