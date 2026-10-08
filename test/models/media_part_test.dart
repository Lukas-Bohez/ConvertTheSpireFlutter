import 'package:convert_the_spire_reborn/src/models/media_part.dart';
import 'package:convert_the_spire_reborn/src/models/queue_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// Downloading only parts of a video or song (issue #41).
void main() {
  Duration s(num v) => Duration(milliseconds: (v * 1000).round());

  test('times as people type them', () {
    expect(MediaPart.parseTime('75'), s(75));
    expect(MediaPart.parseTime('1:15'), s(75));
    expect(MediaPart.parseTime(' 1:02:03 '), s(3723));
    expect(MediaPart.parseTime('1:15.5'), s(75.5));
    expect(MediaPart.parseTime('0,5'), s(0.5));
    for (final bad in ['', 'abc', '1:', ':5', '1:2:3:4', '1:75', '-3']) {
      expect(MediaPart.parseTime(bad), isNull, reason: bad);
    }
  });

  test('labels for files and for yt-dlp', () {
    final part = MediaPart(s(65), s(150.5));
    expect(part.fileLabel, '1m05s-2m30s');
    expect(part.ytDlpSection, '*65.000-150.500');
    expect(MediaPart(s(3723), s(3800)).fileLabel, '1h02m03s-1h03m20s');
    expect(MediaPart.formatTime(s(65)), '1:05');
    expect(MediaPart.formatTime(s(3723)), '1:02:03');
    expect(MediaPart(s(10), s(5)).isValid, isFalse);
  });

  test('two parts of one video are two downloads, kept across restarts', () {
    QueueItem item(MediaPart? part) => QueueItem(
          url: 'https://www.youtube.com/watch?v=x',
          title: 'Song',
          format: 'mp3',
          uploader: null,
          thumbnailBytes: null,
          progress: 0,
          status: DownloadStatus.queued,
          outputPath: null,
          error: null,
          part: part,
        );
    final intro = item(MediaPart(s(0), s(30)));
    final ending = item(MediaPart(s(190), s(220)));
    final whole = item(null);
    expect({intro.key, ending.key, whole.key}, hasLength(3));
    expect(intro == ending, isFalse);
    expect(intro.copyWith(progress: 50).part, intro.part);

    final back = QueueItem.fromJson(ending.toJson());
    expect(back.part, ending.part);
    expect(back.key, ending.key);
    expect(QueueItem.fromJson(whole.toJson()).part, isNull);
  });
}
