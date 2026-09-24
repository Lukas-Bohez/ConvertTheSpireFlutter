# Release Notes - v14.5.0

## Compare that works on phones, and download the whole playlist

### Fixed

* **The app speaks your language, all of it.** Choosing a language in Settings used to change little more than the tab names; almost every screen, dialog and message stayed in English. All 18 languages now cover the whole app: Arabic, Dutch, English, French, German, Hindi, Indonesian, Italian, Japanese, Korean, Polish, Portuguese, Russian, Simplified Chinese, Spanish, Turkish, Ukrainian and Vietnamese. A check in the build now fails if a screen slips back into English.
* **Your settings stay put on Android.** Every setting, the download folder included, was forgotten each time the app closed: the app asked Android where to keep its settings and never got an answer. It keeps them now, so you choose a download folder once.
* **Compare works on phones.** A folder picked on a phone is an Android document address that the scan could not open, so every song showed as missing. The app now reads those folders, and asks Android for a whole folder at a time instead of file by file, so big music folders also open quicker in the player.
* **Compare no longer calls different songs a match.** A title check compared each title with itself, so almost any song "matched" whatever file was left over, on every platform, and the Missing tab came up short. Exact matches are strict now; anything less certain shows its real confidence in the Matched tab.
* **A half-finished download no longer counts as downloaded.** Files like `Song.temp.mp4` and yt-dlp's `.part` files are listed under Extras as incomplete, ready to delete, instead of hiding the song from Missing.
* **Export missing list and Export as M3U work on Android.** Both did nothing on phones.
* **Saving a converted file tells you where it went,** or why it could not be saved. The Save button used to give no sign either way.
* **Compare fits a phone.** The confidence filters, the Missing tab buttons and the Extras headings ran off the edge of the screen; they wrap now. The Quick Download card no longer overflows with larger text.

### New

* **This video or the whole playlist?** Press download while a video plays from a playlist, in the browser or in Quick Download, and the app asks which one you meant. On a playlist page, download takes the playlist. Either way the playlist opens in the Playlist Manager, which first shows the songs you already have. Before, you got only the video, and a playlist page failed. Mixes, Watch Later and Liked videos still download just the video.
* **Open folder is back on the phone player's top bar,** where Watch Together was. Watch Together moves into the ⋮ menu, and returns to the bar while you are in a room. An empty library has its own Open folder button.
* **The player remembers your library.** The folder you open comes back by itself the next time you start the app.
* **The file converter is on Android,** in the Play version too. It was hidden on every Android phone and TV, but the Android app carries FFmpeg, so audio, video, image, document and archive conversions all work there. Converted files go to Downloads/Converted unless you picked a download folder.
* **Extensions on phones.** The browser menu has Extensions on Android too. Full Chrome and Firefox extensions still need the Windows app, so on a phone it shows what does run: the built-in ad blocker, your userscripts, and one-tap searches for popular userscripts such as dark mode, Return YouTube Dislike and SponsorBlock.

### Improved

* Converting shows that it is working, and says why when a conversion fails, instead of leaving the reason in the log.
* Compare remembers the last folder, starts from your download folder, and asks for a folder instead of doing nothing when none is set. Phone folders read "Phone storage/Music" instead of a content:// address, in Compare and in Settings.
* Downloading the missing songs saves them into the folder you compared, next to the rest of the playlist.
* In the Missing tab, tap anywhere on a row to select it.
* A playlist sent from Quick Download keeps the format you chose there.
* A folder with no music in it says so, instead of listing every song as missing.
* Compare skips folders it is not allowed to read, such as Android/data, instead of stopping.
* The Play Store version says that YouTube downloads are not part of it, instead of "Added to queue".
