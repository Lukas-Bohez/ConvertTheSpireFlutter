import 'dart:math';
import 'dart:typed_data';

/// The bytes a peer has sent that are not parsed yet.
///
/// A growable `List<int>` held these before: eight bytes of memory for
/// every byte received, filled one element at a time, and copied whole
/// again after every message taken off the front. On a download that was
/// most of the work of the isolate running it, an app's UI isolate. This
/// keeps the bytes in one [Uint8List], takes messages off the front by
/// moving an offset, and only moves the unread bytes when the end of the
/// buffer is reached.
class ReceiveBuffer {
  static const _initialCapacity = 64 * 1024;

  /// Storage above this size is let go of once it is empty, so one large
  /// message doesn't keep the peer holding on to it.
  static const _keptCapacity = 1024 * 1024;

  Uint8List _data = Uint8List(0);
  int _start = 0;
  int _end = 0;

  int get length => _end - _start;

  bool get isEmpty => _end == _start;

  bool get isNotEmpty => _end != _start;

  int operator [](int index) {
    RangeError.checkValidIndex(index, this, 'index', length);
    return _data[_start + index];
  }

  /// The unread bytes, not copied: valid until the buffer next changes.
  Uint8List get view => Uint8List.sublistView(_data, _start, _end);

  void add(List<int> bytes) {
    if (bytes.isEmpty) return;
    if (_end + bytes.length > _data.length) _makeRoom(bytes.length);
    _data.setRange(_end, _end + bytes.length, bytes);
    _end += bytes.length;
  }

  /// Drops the first [count] unread bytes.
  void consume(int count) {
    RangeError.checkValueInInterval(count, 0, length, 'count');
    _start += count;
    if (_start == _end) clear();
  }

  void clear() {
    _start = 0;
    _end = 0;
    if (_data.length > _keptCapacity) _data = Uint8List(0);
  }

  void _makeRoom(int extra) {
    final unread = length;
    final needed = unread + extra;
    var capacity = _data.length;
    if (needed > capacity) {
      capacity = max(_initialCapacity, capacity * 2);
      while (capacity < needed) {
        capacity *= 2;
      }
    }
    final target = capacity == _data.length ? _data : Uint8List(capacity);
    // setRange copies correctly when the two ranges of _data overlap.
    target.setRange(0, unread, _data, _start);
    _data = target;
    _start = 0;
    _end = unread;
  }
}
