# dtorrent_task_v2 (vendored)

[dtorrent_task_v2](https://pub.dev/packages/dtorrent_task_v2) 0.4.9 from pub.dev
([source](https://github.com/atlet99/dtorrent_task_v2)), BSD 3-Clause (see
`LICENSE`), with two fixes. The first commit that added this folder is the
package exactly as published, so `git log -p third_party/dtorrent_task_v2`
shows the fixes as a plain diff. 0.5.4, the latest release, still has both
bugs.

## Why

Magnet links never got their file list: the app logged "No metadata after
round N" until it gave up. Reproduced against a real libtorrent 2.1 seeder,
which is what qBittorrent and Deluge run on:

| | metadata | 20 MB download |
|---|---|---|
| pub.dev 0.4.9 | libtorrent: `invalid message`, timeout after 45 s | never starts |
| with these fixes | 0.4 s | 4 s, SHA-1 matches |

## The fixes

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

## Updating

Replace `lib/`, `pubspec.yaml`, `CHANGELOG.md` and `LICENSE` with the new
release in one commit, then re-apply the two fixes above in the next (or drop
them if upstream has fixed the bugs).
