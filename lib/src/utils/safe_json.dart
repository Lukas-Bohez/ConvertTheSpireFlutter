import 'dart:convert';

T? safeJsonDecode<T>(String raw) {
  try {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
    return json.decode(trimmed) as T?;
  } catch (_) {
    return null;
  }
}
