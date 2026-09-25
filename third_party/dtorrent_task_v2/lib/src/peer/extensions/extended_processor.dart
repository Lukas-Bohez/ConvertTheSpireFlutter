import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:dtorrent_task_v2/src/peer/peer_base.dart';
import 'package:dtorrent_task_v2/src/peer/protocol/peer_events.dart';
import 'package:events_emitter2/events_emitter2.dart';

mixin ExtendedProcessor on EventsEmittable<PeerEvent> {
  // Remote map of id to extension name
  final Map<int, String> _extendedEventMap = {};
  int _id = 1;

  // The raw `m` dictionary returned from the remote peer
  Map<String, dynamic> _rawMap = {};
  final Map<int, String> _localExtended = <int, String>{};

  Map<String, int> get localExtended {
    var map = <String, int>{};
    _localExtended.forEach((key, value) {
      map[value] = key;
    });
    return map;
  }

  /// Called to register an extension
  /// the id is auto incremented and starts with 1
  void registerExtend(String name) {
    _localExtended[_id] = name;
    _id++;
  }

  int? getExtendedEventId(String name) {
    return _rawMap[name];
  }

  void processExtendMessage(int id, Uint8List message) {
    if (id == 0) {
      // this is a handshake extended message
      var data = decode(message);
      processExtendHandshake(data);
    } else {
      var name = _localExtended[id];
      if (name != null) {
        //TODO: remove the need for casting
        events.emit(ExtendedEvent(this as Peer, name, message));
      }
    }
  }

  void processExtendHandshake(dynamic data) {
    if (data == null || !(data as Map<String, dynamic>).containsKey('m')) {
      // this is not a handshake message
      return;
    }
    var m = data['m'] as Map<String, dynamic>;
    _rawMap = m;
    m.forEach((key, value) {
      if (value == 0) return;
      _extendedEventMap[value] = key;
    });
    //TODO: remove the need for casting
    events.emit(ExtendedEvent(this as Peer, 'handshake', data));
  }

  void clearExtendedProcessors() {
    _extendedEventMap.clear();
    _rawMap.clear();
    _localExtended.clear();
    _id = 1;
  }
}
