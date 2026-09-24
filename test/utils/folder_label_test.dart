import 'package:flutter_test/flutter_test.dart';

import 'package:convert_the_spire_reborn/src/utils/folder_label.dart';

void main() {
  const storage = 'content://com.android.externalstorage.documents/tree';

  test('phone storage folders read as a place and a path', () {
    expect(friendlyFolderLabel('$storage/primary%3AMusic'),
        'Phone storage/Music');
    expect(friendlyFolderLabel('$storage/primary%3AMusic%2FPop'),
        'Phone storage/Music/Pop');
    expect(friendlyFolderLabel('$storage/primary%3A'), 'Phone storage');
  });

  test('a memory card is called an SD card', () {
    expect(friendlyFolderLabel('$storage/1A2B-3C4D%3AMusic'), 'SD card/Music');
  });

  test("the app's own provider shows the real path", () {
    expect(
      friendlyFolderLabel(
          'content://com.torrentspire.ai.github.documents/tree/%2Fstorage%2Femulated%2F0%2FMusic'),
      '/storage/emulated/0/Music',
    );
  });

  test('plain paths and empty values are left alone', () {
    expect(friendlyFolderLabel(r'C:\Users\me\Music'), r'C:\Users\me\Music');
    expect(friendlyFolderLabel('/home/me/Music'), '/home/me/Music');
    expect(friendlyFolderLabel(''), '');
  });
}
