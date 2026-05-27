enum UrlType {
  web,
  magnet,
  torrentFile,
  ipfs,
}

class UrlRoutingService {
  static UrlType detectUrlType(String url) {
    final lower = url.toLowerCase().trim();
    if (lower.startsWith('magnet:')) return UrlType.magnet;
    if (lower.startsWith('ipfs://') || lower.startsWith('ipns://')) {
      return UrlType.ipfs;
    }
    if (_looksLikeRawIpfsCid(lower)) return UrlType.ipfs;
    if (lower.endsWith('.torrent') ||
        lower.contains('/torrent?') ||
        lower.contains('announce') ||
        lower.contains('info_hash')) {
      return UrlType.torrentFile;
    }
    return UrlType.web;
  }

  static bool _looksLikeRawIpfsCid(String lower) {
    if (lower.isEmpty || lower.contains(' ')) return false;
    return lower.startsWith('bafy') || lower.startsWith('qm');
  }
}
