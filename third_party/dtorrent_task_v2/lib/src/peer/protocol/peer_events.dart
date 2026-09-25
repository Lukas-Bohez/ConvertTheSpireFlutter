import 'dart:typed_data';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

abstract class PeerEvent {}

class PeerChokeChanged implements PeerEvent {
  final Peer peer;
  final bool choked;
  PeerChokeChanged(this.peer, this.choked);
}

class PeerInterestedChanged implements PeerEvent {
  final Peer peer;
  final bool interested;

  PeerInterestedChanged(this.peer, this.interested);
}

class PeerConnected implements PeerEvent {
  final Peer peer;

  PeerConnected(this.peer);
}

class PeerKeepAlive implements PeerEvent {
  final Peer peer;

  PeerKeepAlive(this.peer);
}

class PeerCancelEvent implements PeerEvent {
  final Peer peer;
  final int index;
  final int begin;
  final int length;

  PeerCancelEvent(
    this.peer,
    this.index,
    this.begin,
    this.length,
  );
}

class PeerPortChanged implements PeerEvent {
  final Peer peer;
  final int port;
  PeerPortChanged(this.peer, this.port);
}

class PeerHaveAll implements PeerEvent {
  final Peer peer;

  PeerHaveAll(this.peer);
}

class PeerHaveNone implements PeerEvent {
  final Peer peer;

  PeerHaveNone(this.peer);
}

class PeerSuggestPiece implements PeerEvent {
  final Peer peer;
  final int index;

  PeerSuggestPiece(this.peer, this.index);
}

class PeerRejectEvent implements PeerEvent {
  final Peer peer;
  final int index;
  final int begin;
  final int length;

  PeerRejectEvent(this.peer, this.index, this.begin, this.length);
}

class PeerAllowFast implements PeerEvent {
  final Peer peer;
  final int index;
  PeerAllowFast(this.peer, this.index);
}

class PeerRequestEvent implements PeerEvent {
  final Peer peer;
  final int index;
  final int begin;
  final int length;

  PeerRequestEvent(this.peer, this.index, this.begin, this.length);
}

class PeerPieceEvent implements PeerEvent {
  final Peer peer;
  final int index;
  final int begin;
  final Uint8List block;

  PeerPieceEvent(this.peer, this.index, this.begin, this.block);
}

class PeerHaveEvent implements PeerEvent {
  final Peer peer;
  final List<int> indices;

  PeerHaveEvent(this.peer, this.indices);
}

class PeerHandshakeEvent implements PeerEvent {
  final Peer peer;
  final String remotePeerId;
  final List<int> data;

  PeerHandshakeEvent(this.peer, this.remotePeerId, this.data);
}

class PeerBitfieldEvent implements PeerEvent {
  final Peer peer;
  final Bitfield? bitfield;

  PeerBitfieldEvent(this.peer, this.bitfield);
}

class PeerDisposeEvent implements PeerEvent {
  final Peer peer;
  final dynamic reason;

  PeerDisposeEvent(this.peer, this.reason);
}

// extended processor events

class ExtendedEvent implements PeerEvent {
  final Peer peer;
  String eventName;
  dynamic data;
  ExtendedEvent(
    this.peer,
    this.eventName,
    this.data,
  );
}

class RequestTimeoutEvent implements PeerEvent {
  final Peer peer;
  List<List<int>> requests;
  RequestTimeoutEvent(
    this.requests,
    this.peer,
  );
}

// BEP 52 v2 protocol hash messages

class PeerHashRequestEvent implements PeerEvent {
  final Peer peer;
  final Uint8List piecesRoot; // 32 bytes
  final int baseLayer;
  final int index;
  final int length;
  final int proofLayers;

  PeerHashRequestEvent(this.peer, this.piecesRoot, this.baseLayer, this.index,
      this.length, this.proofLayers);
}

class PeerHashesEvent implements PeerEvent {
  final Peer peer;
  final Uint8List piecesRoot; // 32 bytes
  final int baseLayer;
  final int index;
  final int length;
  final int proofLayers;
  final Uint8List hashes;

  PeerHashesEvent(this.peer, this.piecesRoot, this.baseLayer, this.index,
      this.length, this.proofLayers, this.hashes);
}

class PeerHashRejectEvent implements PeerEvent {
  final Peer peer;
  final Uint8List piecesRoot; // 32 bytes
  final int baseLayer;
  final int index;
  final int length;
  final int proofLayers;

  PeerHashRejectEvent(this.peer, this.piecesRoot, this.baseLayer, this.index,
      this.length, this.proofLayers);
}
