# dtorrent_task_v2 (vendored)

[dtorrent_task_v2](https://pub.dev/packages/dtorrent_task_v2) 0.4.9 from pub.dev
([source](https://github.com/atlet99/dtorrent_task_v2)), BSD 3-Clause (see
`LICENSE`), with fixes. The first commit that added this folder is the
package exactly as published, so `git log -p third_party/dtorrent_task_v2`
shows the fixes as a plain diff. 0.5.4, the latest release, still has both
metadata bugs.

## Magnet links


Magnet links never got their file list: the app logged "No metadata after
round N" until it gave up. Reproduced against a real libtorrent 2.1 seeder,
which is what qBittorrent and Deluge run on:

| | metadata | 20 MB download |
|---|---|---|
| pub.dev 0.4.9 | libtorrent: `invalid message`, timeout after 45 s | never starts |
| with these fixes | 0.4 s | 4 s, SHA-1 matches |

### The fixes

1. **The extension handshake goes out first** (`lib/src/peer/protocol/peer.dart`).
   BEP 10 has it sent before any other extended message. It waited for a
   file read (`getTorrentTaskVersion()` reads `pubspec.yaml` from the working
   directory), so the `ut_metadata` request that the remote peer's own
   extension handshake triggers went out before it. libtorrent drops a peer
   that does that ("invalid message"). The handshake is now built and sent
   synchronously, with the version from `PACKAGE_VERSION`
   (`lib/dtorrent_task_v2.dart`).
2. **A peer that disconnects stops being asked for metadata**
   (`lib/src/metadata/metadata_downloader.dart`). It stayed in the list of
   metadata sources, so each retry went to the dead connection and its pieces
   only came back after their timeout; with the dead peer first in the list,
   the download never finished. Its pieces now go to the other peers at once.

## Downloads that froze the app

The download runs on the isolate that runs the app's UI, and it kept that
isolate busy: on a low-end PC the app stopped responding while a torrent
downloaded, and a disk slower than the network filled the memory until the
whole computer froze. Measured with a 600 MB torrent from a local libtorrent
seeder at 10 MB/s, compiled ahead of time and pinned to one CPU core (the
hashing isolate shares that core, so its time is counted too):

| | CPU time | UI stalls: 99th percentile, worst | peak memory |
|---|---|---|---|
| 1 MB pieces, before | 26.4 s | 29 ms, 44 ms | 232 MB |
| 1 MB pieces, after | 11.9 s | 7 ms, 23 ms | 193 MB |
| 64 KB pieces, before | 37.5 s | 34 ms, 119 ms | 234 MB |
| 64 KB pieces, after | 13.6 s | 11 ms, 31 ms | 84 MB |
| 1 MB pieces, 4 MB/s disk, before | 26.5 s | 19 ms, 114 ms | 544 MB, growing with the torrent |
| 1 MB pieces, 4 MB/s disk, after | 12.8 s | 4 ms, 62 ms | 160 MB |

A slower CPU needs several times that CPU time for the same download: before,
the download alone could take all of it.

### The fixes

3. **The bytes from a peer go in one `Uint8List`**
   (`lib/src/peer/protocol/receive_buffer.dart`, used by `peer.dart`). A
   growable `List<int>` held them: eight bytes of memory per byte received,
   filled one element at a time, and copied whole again after every message.
   That was more than half of the download's CPU time.
4. **Pieces are hashed on a background isolate**
   (`lib/src/piece/piece_hasher.dart`, used by `piece.dart`,
   `piece_manager.dart` and `file_validator.dart`). Each piece's SHA-1 held
   up the UI isolate for as long as it took: half a second for a 16 MB piece
   on a slow CPU. Where no isolate can start, pieces are hashed as before.
   A checked piece's bytes also go to the disk without being copied again.
5. **A disk slower than the network holds the download back**
   (`lib/src/task.dart`, `maxUnwrittenBytes`). Checked pieces waiting to be
   written piled up in memory without limit; now no more blocks are asked
   for while more than 64 MB (or four pieces) wait for the disk.
6. **The state file is written at most every two seconds, in one write**
   (`lib/src/file/state_file_v2.dart`). After every piece it was rewritten in
   many small writes, one per completed piece while under 10% were done, and
   flushed to the disk; for torrents of 8192 pieces or more it also patched
   single bytes into a gzip-compressed bitfield. Changes still take effect
   at once, and the file is written on close.
7. **Stopping a torrent while it writes no longer throws**
   (`lib/src/file/download_file.dart`, `lib/src/task.dart`). A write or flush
   that came after its file closed reopened the file and leaked the handle,
   or threw "Cannot add event after closing"; a piece finished just after
   the stop hit a null check.

## Updating

Replace `lib/`, `pubspec.yaml`, `CHANGELOG.md` and `LICENSE` with the new
release in one commit, then re-apply the fixes above in the next (or drop
them if upstream has fixed the bugs).
