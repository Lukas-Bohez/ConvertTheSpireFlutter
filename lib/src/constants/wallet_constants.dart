/// Qubic blockchain wallet and pool endpoint constants.
///
/// All mining rewards earned through the Support tab go to the developer's
/// wallet below.  These values are referenced by [QubicService] and the
/// miner configuration layer.
abstract final class WalletConstants {
  /// Developer's Qubic wallet address.
  static const walletId =
      'EBFXZGMDRBEBQAAJDHOTGJPPXEFBUAGHIUKAFVQYFBDGHXVZIKTUTFKBOJIK';

  /// Qubic blockchain RPC endpoint.
  static const rpcUrl = 'https://rpc.qubic.org';

  /// Qubic mining pool WebSocket endpoint (used by qli-Client).
  static const poolUrl = 'wss://wps.qubic.li/ws';

  /// Pool dashboard web UI.
  static const poolDashboardUrl = 'https://pool.qubic.li';

  /// Qubic explorer URL for the developer wallet.
  static String get explorerUrl =>
      'https://explorer.qubic.org/network/address/$walletId';
}
