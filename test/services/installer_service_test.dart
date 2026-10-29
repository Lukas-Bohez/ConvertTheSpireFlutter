import 'dart:io';

import 'package:convert_the_spire_reborn/src/services/installer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('where FFmpeg is downloaded from', () {
    test('Windows: the essentials zip', () {
      expect(InstallerService.ffmpegDownloadUrl(windows: true).toString(),
          endsWith('ffmpeg-release-essentials.zip'));
    });

    test('Linux: the shared build for the processor', () {
      expect(
          InstallerService.ffmpegDownloadUrl(
                  windows: false, linux: true, arm64: false)
              .toString(),
          'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/'
          'ffmpeg-master-latest-linux64-gpl-shared.tar.xz');
      expect(
          InstallerService.ffmpegDownloadUrl(
                  windows: false, linux: true, arm64: true)
              .toString(),
          endsWith('ffmpeg-master-latest-linuxarm64-gpl-shared.tar.xz'));
    });

    test('macOS: none (Homebrew)', () {
      expect(InstallerService.ffmpegDownloadUrl(windows: false, linux: false),
          isNull);
    });
  });

  test('finds bin/ffmpeg in a Linux build, not the share folder', () async {
    final root = await Directory.systemTemp.createTemp('ffmpeg_find');
    addTearDown(() => root.delete(recursive: true));
    final build = p.join(root.path, 'ffmpeg-master-latest-linux64-gpl-shared');
    await File(p.join(build, 'share', 'doc', 'ffmpeg')).create(recursive: true);
    await File(p.join(build, 'bin', 'ffprobe')).create(recursive: true);
    final ffmpeg = File(p.join(build, 'bin', 'ffmpeg'));
    await ffmpeg.create(recursive: true);

    expect(
        await InstallerService.findFfmpegIn(root, windows: false), ffmpeg.path);
    expect(await InstallerService.findFfmpegIn(root, windows: true), isNull);
    expect(
        await InstallerService.findFfmpegIn(
            Directory(p.join(root.path, 'missing')),
            windows: false),
        isNull);
  });
}
