import 'dart:io';
import 'dart:convert';
import 'proxy_config.dart';

/// HTTP/HTTPS proxy client for tracker requests
class HttpProxyClient {
  final ProxyConfig config;

  HttpProxyClient(this.config) {
    if (config.type != ProxyType.http && config.type != ProxyType.https) {
      throw ArgumentError('HttpProxyClient only supports HTTP/HTTPS proxies');
    }
  }

  /// Create HTTP client with proxy configuration
  ///
  /// Note: Dart's http package doesn't natively support HTTP proxies.
  /// This method returns a configured client that can be used with
  /// custom proxy handling in HTTP requests.
  ///
  /// For actual proxy support, you need to:
  /// 1. Use a proxy-aware HTTP client library, or
  /// 2. Manually handle CONNECT method for HTTPS, or
  /// 3. Use SOCKS5 for peer connections
  Future<HttpClient> createHttpClient() async {
    final client = HttpClient();

    // Set proxy configuration
    client.findProxy = (uri) {
      if (config.useForTrackers) {
        return 'PROXY ${config.host}:${config.port}';
      }
      return 'DIRECT';
    };

    // Set authentication if provided
    if (config.requiresAuth) {
      client.authenticate = (uri, scheme, realm) {
        if (scheme.toLowerCase() == 'basic') {
          // Credentials will be set via Proxy-Authorization header
          return Future.value(true);
        }
        return Future.value(false);
      };
    }

    return client;
  }

  /// Build proxy authorization header
  String? getProxyAuthHeader() {
    if (!config.requiresAuth) return null;

    final credentials = base64Encode(
      utf8.encode('${config.username}:${config.password ?? ''}'),
    );
    return 'Basic $credentials';
  }

  /// Get proxy URL for HTTP requests
  String getProxyUrl() {
    final scheme = config.type == ProxyType.https ? 'https' : 'http';
    return '$scheme://${config.host}:${config.port}';
  }
}
