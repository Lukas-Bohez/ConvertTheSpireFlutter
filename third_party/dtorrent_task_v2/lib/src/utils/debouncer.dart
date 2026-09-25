import 'dart:async';

/// Debouncer for events - delays event emission until a period of inactivity
class Debouncer<T> {
  final Duration delay;
  final void Function(T) callback;
  Timer? _timer;
  T? _lastValue;

  Debouncer(this.delay, this.callback);

  void call(T value) {
    _lastValue = value;
    _timer?.cancel();
    _timer = Timer(delay, () {
      if (_lastValue != null) {
        callback(_lastValue as T);
        _lastValue = null;
      }
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _lastValue = null;
  }

  /// Immediately emit the last value if any
  void flush() {
    _timer?.cancel();
    if (_lastValue != null) {
      callback(_lastValue as T);
      _lastValue = null;
    }
  }
}
