/// A folder as a person would name it.
///
/// Android's folder picker hands back SAF tree URIs such as
/// `content://com.android.externalstorage.documents/tree/primary%3AMusic`,
/// which mean nothing to anyone. This turns them into "Phone storage/Music"
/// or "SD card/Music". Plain paths come back unchanged.
String friendlyFolderLabel(String folder) {
  final value = folder.trim();
  if (value.isEmpty || !value.startsWith('content://')) return value;

  final uri = Uri.tryParse(value);
  final segments = uri?.pathSegments ?? const <String>[];
  final treeAt = segments.indexOf('tree');
  if (treeAt < 0 || treeAt + 1 >= segments.length) return value;
  // pathSegments are already decoded: "primary:Music/Pop".
  final treeId = segments[treeAt + 1];

  // The app's own provider uses the absolute path as the id.
  if (treeId.startsWith('/')) return treeId;

  final colon = treeId.indexOf(':');
  if (colon < 0) return treeId;
  final volume = treeId.substring(0, colon);
  final path = treeId.substring(colon + 1);
  // The Downloads provider's "raw:/storage/emulated/0/Download/x".
  if (volume == 'raw' && path.startsWith('/')) return path;
  final String place;
  if (volume == 'primary') {
    place = 'Phone storage';
  } else if (RegExp(r'^[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}$').hasMatch(volume)) {
    place = 'SD card';
  } else if (volume == 'home') {
    // DocumentsUI's "Documents" root.
    place = 'Documents';
  } else if (volume == 'downloads') {
    place = 'Downloads';
  } else {
    place = volume;
  }
  return path.isEmpty ? place : '$place/$path';
}
