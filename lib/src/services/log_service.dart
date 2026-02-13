import 'package:flutter/foundation.dart';

class LogService {
  final ValueNotifier<List<String>> logs = ValueNotifier<List<String>>(<String>[]);

  void add(String message) {
    final next = List<String>.from(logs.value)..add(message);
    logs.value = next;
  }

  void clear() {
    logs.value = <String>[];
  }
}
