import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

/// Qubic blockchain helper — wallet constants and RPC queries.
///
/// All mining rewards earned through the Support tab go to the developer's
/// wallet below.
class QubicService {
  QubicService._();

  /// Developer's Qubic wallet address.
  static const walletId =
      'EBFXZGMDRBEBQAAJDHOTGJPPXEFBUAGHIUKAFVQYFBDGHXVZIKTUTFKBOJIK';

  /// Qubic blockchain RPC endpoint.
  static const rpcUrl = 'https://rpc.qubic.org';

  /// Qubic mining pool (WebSocket endpoint used by qli-Client).
  static const poolUrl = 'wss://wps.qubic.li/ws';

  /// Pool dashboard (login with Qubic address to see stats).
  static const poolDashboardUrl = 'https://pool.qubic.li';

  /// Qubic explorer for viewing the wallet publicly.
  static String get explorerUrl =>
      'https://explorer.qubic.org/network/address/$walletId';

  /// Fetch wallet balance from the Qubic RPC.
  ///
  /// Returns the balance in QUBIC, or `null` on failure.
  static Future<int?> fetchBalance() async {
    try {
      final uri = Uri.parse('$rpcUrl/v1/balances/$walletId');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        // The RPC wraps the response in a "balance" object.
        final bal = body['balance'];
        if (bal is Map) {
          final raw = bal['balance'];
          if (raw is int) return raw;
          if (raw is num) return raw.toInt();
          if (raw is String) return int.tryParse(raw);
        }
        if (bal is int) return bal;
        if (bal is num) return bal.toInt();
        if (bal is String) return int.tryParse(bal);
      }
    } catch (e) {
      debugPrint('QubicService: balance fetch failed: $e');
    }
    return null;
  }

  /// Fetch current Qubic network tick info.
  static Future<Map<String, dynamic>?> fetchTickInfo() async {
    try {
      final uri = Uri.parse('$rpcUrl/v1/tick-info');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('QubicService: tick-info fetch failed: $e');
    }
    return null;
  }
}
