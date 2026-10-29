import 'dart:io';

import 'package:convert_the_spire_reborn/src/services/open_request_service.dart';
import 'package:convert_the_spire_reborn/src/services/shortcut_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mime/mime.dart';

/// The desktop shortcut (issue #47): the Microsoft Store version's opens the
/// app through Windows instead of its exe inside WindowsApps, and Linux gets
/// a menu entry.
void main() {
  const storeId =
      'OrokaConner.ConvertTheSpireReborn_zbvcx9hwcv0q2!convertthespirereborn';
  const exe = r'C:\Users\Me\AppData\Local\Programs\ConvertTheSpireReborn'
      r'\convert_the_spire_reborn.exe';

  group('Windows shortcut script', () {
    test('the Store version opens the app through the Apps folder', () {
      final script = ShortcutService.windowsScript(
        name: 'Convert the Spire Reborn',
        exePath: r'C:\Program Files\WindowsApps\Pkg_16.1.0.0_x64__abc'
            r'\convert_the_spire_reborn.exe',
        appId: storeId,
        create: true,
      );
      expect(script, contains("TargetPath = 'shell:AppsFolder\\$storeId'"));
      expect(script, isNot(contains('WindowsApps\\Pkg')));
      expect(script, isNot(contains('WorkingDirectory')));
      // A shortcut to the exe inside WindowsApps is replaced.
      expect(script, contains(r"-notlike '*\WindowsApps\*'"));
    });

    test('other builds point at their exe', () {
      final script = ShortcutService.windowsScript(
        name: 'Convert the Spire Reborn',
        exePath: exe,
        create: true,
      );
      expect(script, contains("TargetPath = '$exe'"));
      expect(
          script,
          contains("WorkingDirectory = 'C:\\Users\\Me\\AppData\\Local"
              "\\Programs\\ConvertTheSpireReborn'"));
    });

    test('a deleted shortcut is not made again', () {
      final again =
          ShortcutService.windowsScript(name: 'X', exePath: exe, create: false);
      expect(again, contains('} else { exit 0 }'));
      final first =
          ShortcutService.windowsScript(name: 'X', exePath: exe, create: true);
      expect(first, isNot(contains('} else { exit 0 }')));
    });

    test('quotes are escaped', () {
      final script = ShortcutService.windowsScript(
        name: "Lukas' app",
        exePath: r"C:\It's here\app.exe",
        create: true,
      );
      expect(script, contains("'Lukas'' app.lnk'"));
      expect(script, contains(r"TargetPath = 'C:\It''s here\app.exe'"));
    });

    test('runs: puts a broken shortcut right and keeps a working one',
        () async {
      final dir = await Directory.systemTemp.createTemp('shortcut_test');
      addTearDown(() => dir.delete(recursive: true));
      final app = File('${dir.path}\\app\\convert_the_spire_reborn.exe');
      await app.create(recursive: true);

      Future<String> target(String lnk) async {
        final r = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          "(New-Object -ComObject WScript.Shell).CreateShortcut('$lnk').TargetPath",
        ]);
        return r.stdout.toString().trim();
      }

      Future<int> run({required bool create}) async {
        final r = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          ShortcutService.windowsScript(
            name: 'Test App',
            exePath: app.path,
            create: create,
            desktop: dir.path,
          ),
        ]);
        return r.exitCode;
      }

      final lnk = '${dir.path}\\Test App.lnk';
      // Deleted by the user: stays deleted.
      expect(await run(create: false), 0);
      expect(File(lnk).existsSync(), isFalse);

      // A shortcut to the Store version's exe inside WindowsApps.
      final broken = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "\$s = (New-Object -ComObject WScript.Shell).CreateShortcut('$lnk'); "
            r"$s.TargetPath = 'C:\Program Files\WindowsApps\Pkg_16.0.1.0_x64__abc\app.exe'; "
            r'$s.Save()',
      ]);
      expect(broken.exitCode, 0);
      expect(await target(lnk), contains('WindowsApps'));

      expect(await run(create: false), 0);
      // The same file: the temp folder can be a short 8.3 path (RUNNER~1)
      // that the shortcut stores in full.
      expect(File(await target(lnk)).resolveSymbolicLinksSync(),
          app.resolveSymbolicLinksSync());

      // A working one is left as it is.
      final modified = File(lnk).lastModifiedSync();
      expect(await run(create: true), 0);
      expect(File(lnk).lastModifiedSync(), modified);
    }, skip: !Platform.isWindows);
  });

  group('Linux menu entry', () {
    test('quotes the program and passes what to open', () {
      final entry = ShortcutService.linuxDesktopEntry(
        name: 'Convert the Spire Reborn',
        exec: r'/home/me/Apps/My $pecial 100% "app".AppImage',
        icon: '/home/me/.local/share/app/app_icon.png',
      );
      expect(
          entry,
          contains(r'Exec="/home/me/Apps/My \$pecial 100%% \"app\".AppImage" '
              '%U'));
      expect(entry, contains('Icon=/home/me/.local/share/app/app_icon.png'));
      expect(entry, startsWith('[Desktop Entry]\nType=Application\n'));
      expect(entry,
          contains('StartupWMClass=com.example.convert_the_spire_reborn'));
    });

    test('offers the app for what it opens on the other platforms', () {
      // What the mime package does not know.
      const known = {'.opus': 'audio/opus'};
      for (final extension in OpenRequestService.mediaExtensions) {
        final type = known[extension] ?? lookupMimeType('file$extension');
        expect(type, isNotNull, reason: extension);
        expect(ShortcutService.linuxMimeTypes, contains(type),
            reason: '$extension is $type');
      }
      expect(ShortcutService.linuxMimeTypes,
          containsAll(['x-scheme-handler/magnet', 'application/x-bittorrent']));
    });
  });
}
