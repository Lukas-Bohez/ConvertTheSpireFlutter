import 'dart:async';

enum FileRequestType { read, write, flush }

abstract class FileRequest {
  final FileRequestType type;
  const FileRequest(this.type);
}

class ReadRequest implements FileRequest {
  @override
  final FileRequestType type = FileRequestType.read;
  final Completer<List<int>> completer;
  final int position;
  final int length;
  const ReadRequest({
    required this.completer,
    required this.position,
    required this.length,
  });
}

class WriteRequest implements FileRequest {
  @override
  final FileRequestType type = FileRequestType.write;
  final int position;
  final int start;
  final int end;
  final List<int> block;
  final Completer<bool> completer;
  const WriteRequest({
    required this.position,
    required this.start,
    required this.end,
    required this.block,
    required this.completer,
  });
}

class FlushRequest implements FileRequest {
  @override
  final FileRequestType type = FileRequestType.flush;
  final Completer<bool> completer;
  const FlushRequest({
    required this.completer,
  });
}
