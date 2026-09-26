import 'package:metadata_god/metadata_god.dart';

Future<void>? _initialized;

/// Initializes metadata_god once for the whole app.
///
/// It may only be initialized once: every tag read and write called
/// `MetadataGod.initialize()` again, and the second call threw, which
/// switched the native tag reader off for the session and made writing tags
/// ("Fix metadata") do nothing.
Future<void> ensureMetadataGod() => _initialized ??= MetadataGod.initialize();
