import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';

// Helper functions to shift heavy operations in the bittorrent engine off of the main UI isolate.
// This is an initial infrastructure layer; additional workload can be moved into this isolate
// boundary as effort permits.

Future<Uint8List> decodeTorrentMetaData(Uint8List torrentData) async {
  return compute(_decodeTorrentMetaData, torrentData);
}

Uint8List _decodeTorrentMetaData(Uint8List torrentData) {
  // placeholder for actual parser behavior; this is a safe crossing point for heavy parsing.
  return torrentData;
}

Future<List<int>> hashPieceIsolate(Uint8List pieceData) async {
  return compute(_hashPiece, pieceData);
}

List<int> _hashPiece(Uint8List pieceData) {
  // Operation for example heavy CPU-bound operation on torrent piece.
  // Calculate SHA-1 of the piece and return the bytes.
  return sha1.convert(pieceData).bytes;
}

// TODO: move DHT routing (find_node / peer discovery) into compute() or dedicated Isolate path.
// Since this is the I/O/CPU-heavy engine core, we should make session routing/piece checks invoke
// isolate boundaries exclusively before they touch UI state.
