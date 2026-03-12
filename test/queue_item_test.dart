import 'package:flutter_test/flutter_test.dart';
import 'package:convert_the_spire_reborn/src/models/queue_item.dart';

void main() {
  group('QueueItem', () {
    test('copyWith preserves unchanged fields', () {
      const item = QueueItem(
        url: 'https://example.com/video',
        title: 'Test Video',
        format: 'mp4',
        uploader: 'Tester',
        thumbnailBytes: null,
        progress: 0,
        status: DownloadStatus.queued,
        outputPath: null,
        error: null,
      );

      final updated =
          item.copyWith(progress: 50, status: DownloadStatus.downloading);
      expect(updated.url, 'https://example.com/video');
      expect(updated.title, 'Test Video');
      expect(updated.format, 'mp4');
      expect(updated.uploader, 'Tester');
      expect(updated.progress, 50);
      expect(updated.status, DownloadStatus.downloading);
      expect(updated.outputPath, isNull);
      expect(updated.error, isNull);
    });

    test('copyWith can set outputPath to null', () {
      const item = QueueItem(
        url: 'https://example.com/video',
        title: 'Test Video',
        format: 'mp4',
        uploader: null,
        thumbnailBytes: null,
        progress: 100,
        status: DownloadStatus.completed,
        outputPath: '/path/to/file.mp4',
        error: null,
      );

      final updated = item.copyWith(outputPath: null);
      expect(updated.outputPath, isNull);
    });

    test('equality based on url + format', () {
      const a = QueueItem(
        url: 'https://example.com/video',
        title: 'Title A',
        format: 'mp4',
        uploader: null,
        thumbnailBytes: null,
        progress: 0,
        status: DownloadStatus.queued,
        outputPath: null,
        error: null,
      );
      const b = QueueItem(
        url: 'https://example.com/video',
        title: 'Title B',
        format: 'mp4',
        uploader: 'Someone',
        thumbnailBytes: null,
        progress: 50,
        status: DownloadStatus.downloading,
        outputPath: null,
        error: null,
      );
      const c = QueueItem(
        url: 'https://example.com/video',
        title: 'Title A',
        format: 'mp3',
        uploader: null,
        thumbnailBytes: null,
        progress: 0,
        status: DownloadStatus.queued,
        outputPath: null,
        error: null,
      );

      expect(a, equals(b)); // same url + format
      expect(a, isNot(equals(c))); // different format
      expect(a.hashCode, b.hashCode);
    });
  });

  group('DownloadStatus', () {
    test('all expected values exist', () {
      expect(
          DownloadStatus.values,
          containsAll([
            DownloadStatus.queued,
            DownloadStatus.downloading,
            DownloadStatus.converting,
            DownloadStatus.completed,
            DownloadStatus.failed,
            DownloadStatus.cancelled,
          ]));
    });
  });
}
