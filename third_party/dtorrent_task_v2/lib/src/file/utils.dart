import 'package:dtorrent_task_v2/src/file/download_file.dart';

class FileBlockPosition {
  int position;
  int blockStart;
  int blockEnd;
  FileBlockPosition({
    required this.position,
    required this.blockStart,
    required this.blockEnd,
  });
}

//
// start: is start position relative to the entire torrent block
// endByte: is end position relative to the entire torrent block
//

FileBlockPosition? blockToDownloadFilePosition(
    int start, int end, int blockSize, DownloadFile tempFile) {
  var fileStartByte = tempFile.offset;
  var fileEndByte = fileStartByte + tempFile.length;
  if (end < fileStartByte || start > fileEndByte) return null;
  var filePosition = 0;
  var blockStart = 0;
  // block start is entirely inside the file
  if (start >= fileStartByte) {
    // position relative to the start of the file
    filePosition = start - fileStartByte;
    blockStart = 0;
  } else {
    //  some of the block belongs to the previous file
    // the position is 0 since we will only write bytes that belong to this file
    filePosition = 0;
    // this is the start position of the block that we care about
    // it is also the size of block that should be discarded
    blockStart = fileStartByte - start;
  }
  var blockEnd = blockStart;
  // block end is entirely inside the file
  if (fileEndByte >= end) {
    // use entire block
    blockEnd = blockSize;
  } else {
    //  some of the block belongs to the next file
    blockEnd = fileEndByte - start;
  }
  return FileBlockPosition(
      position: filePosition, blockStart: blockStart, blockEnd: blockEnd);
}
