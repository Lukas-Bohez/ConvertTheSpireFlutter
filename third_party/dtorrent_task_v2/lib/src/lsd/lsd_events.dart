import 'package:dtorrent_common/dtorrent_common.dart';

abstract class LSDEvent {}

class LSDNewPeer implements LSDEvent {
  CompactAddress address;
  String infoHashHex;
  LSDNewPeer(
    this.address,
    this.infoHashHex,
  );
}
