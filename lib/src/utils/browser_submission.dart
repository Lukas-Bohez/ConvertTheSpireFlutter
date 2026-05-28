enum BrowserSubmissionKind {
  internalRoute,
  openUrl,
  magnet,
}

class BrowserSubmissionDecision {
  final BrowserSubmissionKind kind;
  final String value;

  const BrowserSubmissionDecision(this.kind, this.value);
}

BrowserSubmissionDecision resolveBrowserSubmission(
  String input, {
  required Map<String, int> routeToIndex,
  required Map<int, String> indexToRoute,
  required Map<int, String> indexToTitle,
}) {
  final trimmed = input.trim();
  final lower = trimmed.toLowerCase();

  if (routeToIndex.containsKey(lower)) {
    return BrowserSubmissionDecision(
        BrowserSubmissionKind.internalRoute, lower);
  }

  for (final entry in indexToTitle.entries) {
    if (entry.value.toLowerCase() == lower) {
      final route = indexToRoute[entry.key];
      if (route != null) {
        return BrowserSubmissionDecision(
            BrowserSubmissionKind.internalRoute, route);
      }
    }
  }

  if (lower.startsWith('magnet:')) {
    return BrowserSubmissionDecision(BrowserSubmissionKind.magnet, trimmed);
  }

  if (lower.startsWith('ipfs://') || lower.startsWith('ipns://')) {
    return BrowserSubmissionDecision(BrowserSubmissionKind.openUrl, trimmed);
  }

  final looksLikeUrl = lower.startsWith('http') ||
      (trimmed.contains('.') && !trimmed.contains(' ') && trimmed.length > 4);
  if (looksLikeUrl) {
    final normalized =
        trimmed.startsWith('http') ? trimmed : 'https://$trimmed';
    return BrowserSubmissionDecision(BrowserSubmissionKind.openUrl, normalized);
  }

  return BrowserSubmissionDecision(
    BrowserSubmissionKind.openUrl,
    'https://www.google.com/search?q=${Uri.encodeComponent(trimmed)}',
  );
}
