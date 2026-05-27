import 'package:shared_preferences/shared_preferences.dart';

class IpfsService {
  static const List<String> _gateways = <String>[
    'https://ipfs.io',
    'https://cloudflare-ipfs.com',
    'https://gateway.pinata.cloud',
    'https://dweb.link',
  ];

  static const String _prefCustomGateway = 'browser_ipfs_gateway';

  static Future<String?> getCustomGateway() async {
    final prefs = await SharedPreferences.getInstance();
    final gateway = prefs.getString(_prefCustomGateway)?.trim() ?? '';
    return gateway.isEmpty ? null : _normalizeGateway(gateway);
  }

  static Future<void> setCustomGateway(String? gateway) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = gateway?.trim() ?? '';
    if (normalized.isEmpty) {
      await prefs.remove(_prefCustomGateway);
      return;
    }
    await prefs.setString(_prefCustomGateway, _normalizeGateway(normalized));
  }

  static Future<String> resolveUrl(String ipfsUrl) async {
    final gateway = (await getCustomGateway()) ?? _gateways.first;
    final trimmed = ipfsUrl.trim();
    final lower = trimmed.toLowerCase();

    if (lower.startsWith('ipfs://')) {
      final cid = trimmed.substring(7);
      return '$gateway/ipfs/$cid';
    }
    if (lower.startsWith('ipns://')) {
      final name = trimmed.substring(7);
      return '$gateway/ipns/$name';
    }
    if (lower.startsWith('bafy') || lower.startsWith('qm')) {
      return '$gateway/ipfs/$trimmed';
    }
    return trimmed;
  }

  static List<String> get gateways => List.unmodifiable(_gateways);

  static String _normalizeGateway(String gateway) {
    var normalized = gateway.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}
