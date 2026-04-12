import 'dart:io';

import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';

Future<void> initSqlCipherOnAndroid() async {
  if (Platform.isAndroid) {
    // Keep this as a best-effort hook; newer sqlcipher_flutter_libs versions
    // no longer expose the old Android workaround API used previously.
    await Future<void>.value();
  }
}
