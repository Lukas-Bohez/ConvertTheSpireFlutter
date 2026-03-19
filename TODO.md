It sounds like you are moving from the UI/UX polish phase into the deep mechanics of the app. Dealing with background tasks and downloads on Android is notoriously tricky because the operating system aggressively kills apps to save battery, so it is completely normal that you hit a wall here! 

Here is a comprehensive, structured `TODO.md` focused on core functionality, background processing, and download reliability. This will show your teacher that you understand how to build robust, fault-tolerant logic, not just pretty screens.

***

# 🛠️ Phase 2: Core Functionality & Reliability

## 🛑 Critical Logic Repairs
- [x] **Wire up the Refresh Button:** - Connect the refresh button to your state management solution (e.g., Provider, Riverpod).
    - Ensure it triggers a re-scan of the current local directory and re-fetches playlist metadata from the web.
    - Add a loading spinner (`CircularProgressIndicator`) that shows *only* while the refresh is active.
- [x] **Fix "Watched Playlists" Data Model:**
    - Create a data structure (and save it locally using SQLite, Hive, or SharedPreferences) that links a `Playlist URL` to a specific `Local Directory Path`.
    - Ensure the UI correctly displays these linked pairs and allows the user to edit or delete the connection.

## 📥 Robust Download Engine (Android Sleep Mode Fix)
- [x] **Implement Background Downloading:**
    - **The Problem:** Standard HTTP requests in Flutter die when the Android screen turns off. 
    - **The Fix:** AppController uses `downloadAll()` queue with controlled worker count and notification keepalive; for offline runtime, this is the basis for future `workmanager` integration.
- [x] **Auto-Retry & Resilience:**
    - Implement a retry mechanism for failed downloads (e.g., attempt to download 3 times before failing).
    - Catch specific network exceptions (like `SocketException` or `TimeoutException`) and pause the download queue if the internet disconnects, rather than crashing or failing silently.
- [x] **Download Queue Management:**
    - Prevent the app from downloading 20 files at once (which will crash the app or get blocked by the server). Limit concurrent downloads to 2 or 3.

## 🔄 The "Watch" & Sync System
- [ ] **Playlist Diffing Logic:**
    - Create a function that fetches the playlist from the internet, lists the files currently in the local linked folder, and compares the two.
    - Isolate the "new" parts that exist online but not locally, and push *only* those to the download queue.
- [ ] **Automated Sync Task:**
    - Implement a background scheduler (using the `workmanager` package) that runs this "Diffing Logic" periodically (e.g., every few hours or once a day) to automatically queue up new videos/audio without the user opening the app.

## 🛡️ Edge Cases & UX State Handling
- [ ] **Storage Management:** Before starting a big download, check if the device has enough free storage space. Show a friendly error alert if it doesn't.
- [ ] **Granular Permissions:** Ensure you are correctly requesting Android 13/14+ media permissions (`READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO`) and standard notification permissions to show download progress.
- [ ] **Cancel/Pause Controls:** Give the user the ability to cancel an ongoing download or remove an item from the queue if they clicked it by mistake.

***

### 💡 Note for your defense/presentation:
When presenting this to your teacher, emphasizing the shift from **foreground HTTP requests** to an **OS-level Background Downloader** is a massive flex. It proves you understand mobile lifecycles (app states like active, inactive, paused, and detached) and aren't just treating a phone like a desktop computer.

Would you like me to look into specific Flutter packages (like `flutter_downloader` vs. `background_downloader`) and give you a breakdown of which one might be easiest to drop into your current architecture?