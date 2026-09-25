import 'piece.dart';

abstract class PieceProvider {
  // Piece getPiece(int index);

  Piece? operator [](int index);

  int get length;
  Set<int> get downloadingPieces;
  Map<int, Piece> get pieces;
}
