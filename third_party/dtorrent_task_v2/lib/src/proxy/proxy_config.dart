/// Proxy configuration for torrent task
class ProxyConfig {
  /// Proxy type
  final ProxyType type;

  /// Proxy host
  final String host;

  /// Proxy port
  final int port;

  /// Username for authentication (optional)
  final String? username;

  /// Password for authentication (optional)
  final String? password;

  /// Whether to use proxy for trackers
  final bool useForTrackers;

  /// Whether to use proxy for peers
  final bool useForPeers;

  ProxyConfig({
    required this.type,
    required this.host,
    required this.port,
    this.username,
    this.password,
    this.useForTrackers = true,
    this.useForPeers = true,
  });

  /// Create HTTP proxy configuration
  factory ProxyConfig.http({
    required String host,
    required int port,
    String? username,
    String? password,
    bool useForTrackers = true,
    bool useForPeers = false,
  }) {
    return ProxyConfig(
      type: ProxyType.http,
      host: host,
      port: port,
      username: username,
      password: password,
      useForTrackers: useForTrackers,
      useForPeers: useForPeers,
    );
  }

  /// Create HTTPS proxy configuration
  factory ProxyConfig.https({
    required String host,
    required int port,
    String? username,
    String? password,
    bool useForTrackers = true,
    bool useForPeers = false,
  }) {
    return ProxyConfig(
      type: ProxyType.https,
      host: host,
      port: port,
      username: username,
      password: password,
      useForTrackers: useForTrackers,
      useForPeers: useForPeers,
    );
  }

  /// Create SOCKS5 proxy configuration
  factory ProxyConfig.socks5({
    required String host,
    required int port,
    String? username,
    String? password,
    bool useForTrackers = false,
    bool useForPeers = true,
  }) {
    return ProxyConfig(
      type: ProxyType.socks5,
      host: host,
      port: port,
      username: username,
      password: password,
      useForTrackers: useForTrackers,
      useForPeers: useForPeers,
    );
  }

  /// Check if authentication is required
  bool get requiresAuth => username != null && username!.isNotEmpty;

  /// Get proxy URI
  Uri get uri {
    final scheme = type == ProxyType.http
        ? 'http'
        : type == ProxyType.https
            ? 'https'
            : 'socks5';
    return Uri(
      scheme: scheme,
      host: host,
      port: port,
      userInfo: requiresAuth ? '$username:$password' : null,
    );
  }

  @override
  String toString() {
    return 'ProxyConfig(type: $type, host: $host, port: $port, '
        'useForTrackers: $useForTrackers, useForPeers: $useForPeers)';
  }
}

/// Proxy type
enum ProxyType {
  /// HTTP proxy
  http,

  /// HTTPS proxy
  https,

  /// SOCKS5 proxy
  socks5,
}
