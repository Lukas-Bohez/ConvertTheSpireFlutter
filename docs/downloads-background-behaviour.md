# What happens to downloads in the background

Written for: anyone maintaining the download path, and anyone answering a
"my downloads stopped" report.

Background: downloads used to stop whenever the screen went off, because
nothing kept the process alive (issue #7). This is what the current behaviour
is, deliberately, so the next report can be checked against it.

## Android

| Situation | What happens |
|---|---|
| Screen off, app in background | Downloads continue. `ForegroundDownloadService` runs with a `dataSync` foreground type and holds a partial wake lock and a wifi lock. |
| App closed with Back, or swiped away from recents | The foreground service keeps the process alive, and `audio_service` keeps the Flutter engine running without an activity, so downloads carry on and the service stops itself when they finish. The method channel lives in `ForegroundBridge`, which holds only the application context, so it keeps working after `MainActivity` is gone. |
| Process killed anyway (some vendors do this on swipe) | The queue is already persisted and resumes on next launch. The service is `START_NOT_STICKY` on purpose: a sticky restart brings the service back without a Flutter engine, which leaves a "downloading" notification with nothing behind it. |
| Stop tapped on the notification | Queue downloads and running torrents are paused, not just the notification dismissed. The service stops and drops its locks. When Dart stops the service itself because the work finished, it uses `stopService`, so that never echoes back as a pause. |
| More than 6 hours of downloading (Android 15+) | The system caps `dataSync` foreground services at 6 hours per 24. `onTimeout` pauses the queue and stops the service rather than letting the app be killed. |
| Battery optimisation not disabled | The OS can still kill the app, foreground service or not. The GitHub build offers the exemption prompt; the Play build cannot, because Play restricts the direct request. Aggressive vendors (Xiaomi, Samsung, Huawei) need their own per-device settings — see dontkillmyapp.com. |
| Notifications permission denied | Downloads still run, but the user sees no progress. The permission is requested with the others at startup. |

The service is started and stopped by `DownloadKeepAlive`, which counts
active work per source so the download queue and torrents do not each try to
hold the process up separately, and one going idle does not stop the service
while the other is still busy. The queue (which includes conversions) reports
on every change; torrents are polled every 3 seconds, and only if the torrent
engine already exists, so the poll never starts DHT on its own. Seeding
torrents do not count: a finished torrent should not hold the phone awake. Stopping is debounced by 5 seconds so a queue that
briefly empties between two items does not tear the service down and
immediately rebuild it, and notification updates are throttled to once a
second.

## Desktop (Windows, macOS, Linux)

Nothing sleeps the process, so downloads continue as long as the app is
running. Closing to the tray keeps them going; quitting does not. The queue is
persisted either way.

## iOS

Not supported. `flutter_background_service` used to be wired up here, but its
isolate got a fresh, empty `TorrentEngineService`, so it could only ever have
reported 0 MB/s. It was removed rather than left looking functional.

## Checking it by hand

With a large torrent and a 20-track playlist queued, and no music playing
(music keeps the process alive on its own through `audio_service`, which is
what made this look intermittent):

    adb shell dumpsys activity services com.torrentspire.ai

should list `ForegroundDownloadService` as foreground. Then:

    adb shell dumpsys deviceidle force-idle

and confirm progress keeps moving.
