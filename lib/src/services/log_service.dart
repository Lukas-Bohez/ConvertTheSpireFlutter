import 'package:flutter/foundation.dart';

class LogService {
  static const int _maxEntries = 500;

  final ValueNotifier<List<String>> logs = ValueNotifier<List<String>>(<String>[]);

  void add(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final next = List<String>.from(logs.value)..add('[$timestamp] $message');
    if (next.length > _maxEntries) {
      next.removeRange(0, next.length - _maxEntries);
    }
    logs.value = next;
  }

  void clear() {
    logs.value = <String>[];
  }
}
