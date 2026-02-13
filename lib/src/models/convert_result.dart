class ConvertResult {
  final String name;
  final String mime;
  final List<int> bytes;
  final String message;

  const ConvertResult({
    required this.name,
    required this.mime,
    required this.bytes,
    required this.message,
  });
}
