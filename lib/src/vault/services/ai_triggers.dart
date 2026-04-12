import 'package:convert_the_spire_reborn/src/vault/services/search_service.dart';

class AiTriggerEvent {
  final String key;
  final String prompt;
  final bool auto;

  const AiTriggerEvent({
    required this.key,
    required this.prompt,
    this.auto = true,
  });
}

class AiTriggers {
  AiTriggerEvent onResultSelected(SearchResult result) {
    final stats = <String>[];
    if ((result.seeders ?? 0) > 0) {
      stats.add('seeders=${result.seeders}');
    }
    if ((result.leechers ?? 0) > 0) {
      stats.add('leechers=${result.leechers}');
    }
    if ((result.ageYears ?? 0) > 0) {
      stats.add('ageYears=${result.ageYears}');
    }
    final observedStats = stats.isEmpty ? 'no positive swarm stats' : stats.join(', ');
    return AiTriggerEvent(
      key: 'result:${result.torrentId}',
      prompt:
          'The user is looking at ${result.name}. '
          'Observed stats: $observedStats. '
          'Give a brief overview: what it likely is and estimated quality. '
          'Do not label it dangerous or suspicious just because seeders are 0, leechers are 0, or age is unknown. '
          'Only mention a red flag if there is direct evidence such as malware, fake packaging, password-protected archives, broken metadata, or contradictory file info.',
    );
  }

  AiTriggerEvent onDownloadStarted({
    required String name,
    required String size,
  }) {
    return AiTriggerEvent(
      key: 'download_started:$name',
      prompt:
          'The user just started downloading $name ($size). Any tips on what to expect, file structure, or how long it might take at typical speeds?',
    );
  }

  AiTriggerEvent onDownloadCompleted(String name) {
    return AiTriggerEvent(
      key: 'download_completed:$name',
      prompt:
          'The user finished downloading $name. What are the next steps - how do they typically use or play this type of file?',
    );
  }

  AiTriggerEvent onZeroResults(String query) {
    return AiTriggerEvent(
      key: 'zero_results:${query.toLowerCase()}',
      prompt:
          "The user searched for '$query' and got no results. Suggest 3 alternative search terms or strategies.",
    );
  }

  AiTriggerEvent onCategoryChanged(String category) {
    return AiTriggerEvent(
      key: 'category:${category.toLowerCase()}',
      prompt:
          'The user is now browsing $category. What should they know about finding quality torrents in this category?',
    );
  }
}
