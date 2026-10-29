/// The SHA-256 of [fileName] in a release's SHA256SUMS.txt, whose lines look
/// like `<hash>  ConvertTheSpireReborn-Setup.exe` (older releases:
/// `<hash>  ./windows-installer/ConvertTheSpireReborn-Setup.exe`). Null when
/// the file is not listed.
String? releaseFileHash(String sums, String fileName) {
  for (final line in sums.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) continue;
    final name = parts.last.replaceAll('\\', '/').split('/').last;
    if (name.toLowerCase() == fileName.toLowerCase() &&
        RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(parts.first)) {
      return parts.first.toLowerCase();
    }
  }
  return null;
}
