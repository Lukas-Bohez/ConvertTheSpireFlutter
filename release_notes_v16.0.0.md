# Convert the Spire Reborn v16.0.0

## A cleaner player, subtitles, and only the part you want

### New

- **Download only the part you want.** Quick Download on Home asks whether you want the whole video or song, or only parts of it. Mark one part or several (from 1:05 to 2:30, say) and each becomes its own file.
- **Subtitles, for videos and songs.** An .srt or .vtt file next to the file, or in a Subs folder, loads by itself. Pick another one, turn them off with one tap (or C), or move them earlier or later when they are out of step.
- **Loop the best part.** Mark one or more parts of a song or video and playback stays in them, from one part to the next.
- **Large view.** The video fills the window with nothing else around it. Esc brings the app back.
- **Playback speed and a sleep timer.** From 0.5× to 2×, and stop after 15 to 60 minutes or at the end of the song.
- **Long videos and podcasts open where you left off**, with Start over one tap away.
- **An ad blocker that blocks.** The browser uses the filter lists uBlock Origin uses (EasyList and EasyPrivacy), stops ads before they load on Windows, and hides what is left.

### Changed

- **One set of player controls.** No more second play button, seek bar, volume or full screen button under the video, no "Player" title, and the video gets the room it needs.
- **Every colour is unlocked in the Microsoft Store version**, as in the GitHub version.
- Like the app? A small card now and then says how to support it. It never interrupts, and once you close it, it stays away for six weeks.

### Fixed

- **A program downloaded by torrent starts while it seeds.** Windows no longer says the file is in use.
- **A torrent of files you already have seeds at once**, instead of sitting at "Stalled 0%".
- **Videos in your library have thumbnails**, and a song you never played no longer says "0 plays".
- The player's scroll bar reaches the bottom of the list.
- A YouTube download no longer fails when the video page can't be read the first time.
- Android: the notification shows the song as soon as it starts, and the 30-second preview stops after 30 seconds.

### Build Notes

- Version 16.0.0+1304. The Microsoft Store package (MSIX) is built by the "Microsoft Store package" workflow or `scripts\make_store_upload.cmd`; see `docs/publishing/windows-store.md`. The Store's "What's new in this version" text for all 18 languages is in `docs/publishing/store-listing/`, and the Google Play listing in `store/google-play/listing/`.
