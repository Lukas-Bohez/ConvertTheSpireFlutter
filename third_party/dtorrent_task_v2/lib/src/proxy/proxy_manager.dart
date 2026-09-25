import 'dart:io';
import 'proxy_config.dart';
import 'http_proxy_client.dart';
import 'socks5_client.dart';

/// Proxy manager for handling proxy configuration and clients
class ProxyManager {
  final ProxyConfig? config;

  HttpProxyClient? _httpProxyClient;
  Socks5Client? _socks5Client;

  ProxyManager(this.config) {
    if (config != null) {
      if (config!.type == ProxyType.http || config!.type == ProxyType.https) {
        _httpProxyClient = HttpProxyClient(config!);
      } else if (config!.type == ProxyType.socks5) {
        _socks5Client = Socks5Client(config!);
      }
    }
  }

  /// Get HTTP proxy client (for trackers)
  HttpProxyClient? get httpProxyClient => _httpProxyClient;

  /// Get SOCKS5 proxy client (for peers)
  Socks5Client? get socks5Client => _socks5Client;

  /// Check if proxy should be used for trackers
  bool shouldUseForTrackers() {
    return config != null && config!.useForTrackers;
  }

  /// Check if proxy should be used for peers
  bool shouldUseForPeers() {
    return config != null && config!.useForPeers;
  }

  /// Create HTTP client with proxy configuration
  Future<HttpClient> createHttpClient() async {
    if (_httpProxyClient != null) {
      return await _httpProxyClient!.createHttpClient();
    }
    return HttpClient();
  }

  /// Connect to target through proxy (for peers)
  Future<Socket> connectThroughProxy(
    InternetAddress targetAddress,
    int targetPort, {
    Duration? timeout,
  }) async {
    if (_socks5Client != null && shouldUseForPeers()) {
      return await _socks5Client!.connect(
        targetAddress,
        targetPort,
        timeout: timeout,
      );
    }

    // Direct connection if no proxy or proxy not configured for peers
    return await Socket.connect(
      targetAddress,
      targetPort,
      timeout: timeout ?? const Duration(seconds: 30),
    );
  }
}
