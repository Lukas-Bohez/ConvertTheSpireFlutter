abstract class PieceManagerEvent {}

class PieceAccepted implements PieceManagerEvent {
  int pieceIndex;
  PieceAccepted(
    this.pieceIndex,
  );
}

class PieceRejected implements PieceManagerEvent {
  final int index;

  PieceRejected(this.index);
}
