import 'dart:io';

import 'package:path/path.dart' as p;

import 'scanner.dart';

/// Scans a folder of browser extensions for the compatibility study (#10).
///
/// ```
/// dart run tools/ext_api_scan/scan.dart <input-folder> [output-folder]
/// ```
///
/// The input may hold unpacked extension folders and .crx, .zip or .xpi
/// packages side by side. Writes `api-usage.csv` and `api-matrix.md` to the
/// output folder, `results/extensions` by default.
Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first == '-h' || args.first == '--help') {
    stdout.writeln(
        'usage: dart run tools/ext_api_scan/scan.dart <input> [output]');
    exitCode = args.isEmpty ? 64 : 0;
    return;
  }
  final input = Directory(args[0]);
  if (!input.existsSync()) {
    stderr.writeln('No such folder: ${input.path}');
    exitCode = 66;
    return;
  }
  final output = Directory(args.length > 1 ? args[1] : 'results/extensions');
  await output.create(recursive: true);

  final (scans, problems) = await scanAll(input);
  await File(p.join(output.path, 'api-usage.csv')).writeAsString(toCsv(scans));
  await File(p.join(output.path, 'api-matrix.md'))
      .writeAsString(toMarkdownMatrix(scans));

  stdout.writeln('Scanned ${scans.length} extension(s) into ${output.path}.');
  for (final problem in problems) {
    stderr.writeln('skipped $problem');
  }
}
