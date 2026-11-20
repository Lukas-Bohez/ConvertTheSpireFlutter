# Getting the app on Flathub

What is ready in this repository, what Flathub asks for, and the steps to
submit. Checked against Flathub's documentation on 20 November 2026
([requirements](https://docs.flathub.org/docs/for-app-authors/requirements),
[submission](https://docs.flathub.org/docs/for-app-authors/submission),
[quality guidelines](https://docs.flathub.org/docs/for-app-authors/metainfo-guidelines/quality-guidelines),
[runtimes](https://docs.flathub.org/docs/for-app-authors/runtimes)). Read them
again before submitting: they change.

## Read this first: Flathub's rules on AI-generated work

Flathub has a generative-AI policy (in the requirements page) that decides who
can do which part of this:

- **The Flathub manifest must not contain AI-generated or AI-assisted
  content.** Disclosing it does not make it acceptable. So the manifest
  (`io.github.Lukas_Bohez.ConvertTheSpireFlutter.yml`) is **not** in this
  repository and was deliberately not written for you: you write it yourself.
- **AI tools must not open or automate the submission pull request**, nor
  write its description, its commit messages or replies to reviewers. Do those
  by hand.
- **AI-generated code, documentation or packaging in the app itself must be
  disclosed** in the submission (which parts, and roughly how much).
  Reviewers decide case by case and may reject it. For this app that covers
  much of the source code, and the files listed under "Ready in this
  repository" below (desktop file, metainfo, icon, the Linux id change), which
  were made with Claude.
- Using AI only for research or discussion, like this guide, needs no
  disclosure as long as nothing it generated ends up in the app or the
  packaging.

## Ready in this repository

| What | Where |
|---|---|
| App id `io.github.Lukas_Bohez.ConvertTheSpireFlutter` (GitHub user with `-` as `_`, then the repository name, as Flathub requires for `io.github` ids) | `linux/CMakeLists.txt` (`APPLICATION_ID`), `lib/src/services/linux_app_id.dart` |
| Desktop file (validated with `desktop-file-validate`) | `linux/packaging/io.github.Lukas_Bohez.ConvertTheSpireFlutter.desktop` |
| AppStream metainfo (validated with `appstreamcli validate`; screenshots still to add, see below) | `linux/packaging/io.github.Lukas_Bohez.ConvertTheSpireFlutter.metainfo.xml` |
| Icon: SVG and PNGs 16 to 512 px | `assets/icons/app-icon.svg`, `assets/icons/linux/<n>x<n>/io.github.Lukas_Bohez.ConvertTheSpireFlutter.png` (from `scripts/make_app_icons.py`) |
| The app behaves as a Flatpak should | Inside a Flatpak (`FLATPAK_ID` set) it does not update itself (Flathub does), does not write its own menu entry or desktop shortcut, and leaves `~/.local/share` alone |

The id changed from Flutter's template `com.example.convert_the_spire_reborn`
in 16.4.1. On first start a Linux install moves its data folder
(`~/.local/share/<id>`, `~/.config/<id>`) to the new id and replaces the old
menu entry, so settings and the library stay.

In a Flatpak these install as:

```
/app/share/applications/io.github.Lukas_Bohez.ConvertTheSpireFlutter.desktop
/app/share/metainfo/io.github.Lukas_Bohez.ConvertTheSpireFlutter.metainfo.xml
/app/share/icons/hicolor/scalable/apps/io.github.Lukas_Bohez.ConvertTheSpireFlutter.svg
/app/share/icons/hicolor/<n>x<n>/apps/io.github.Lukas_Bohez.ConvertTheSpireFlutter.png
```

## Still to decide or do

1. **The name.** Flathub's quality guidelines want a name of at most 15
   characters and under 20 in any case. "Convert the Spire Reborn" is 24.
   Choose a shorter one (for example "BitPlayer", the Play Store name) and
   put it in `<name>` in the metainfo and `Name=` in the desktop file, or
   expect the reviewers to ask.
2. **Screenshots.** At least one is required, 3 to 6 is good. Take them on
   Linux (not Windows), of the app window only, with default settings, at
   1000x700 or smaller (2000x1400 on HiDPI). Put them in the repository, for
   example `docs/screenshots/linux/`, and add to the metainfo, after
   `</description>`:

   ```xml
   <screenshots>
     <screenshot type="default">
       <image>https://raw.githubusercontent.com/Lukas-Bohez/ConvertTheSpireFlutter/v16.4.1/docs/screenshots/linux/player.png</image>
       <caption>The player with lyrics and the library</caption>
     </screenshot>
   </screenshots>
   ```

   Use a tag (as above), not `main`, so the images never change under a
   release. A caption is one sentence without a full stop.
3. **Content rating.** The metainfo has an empty OARS rating. The app has a
   web browser, so pages of any kind are a click away; fill in the
   questionnaire at <https://hughsie.github.io/oars/generate.html> and paste
   the result over `<content_rating type="oars-1.1"/>`.
4. **The license.** The metainfo says `GPL-3.0-only`. If you mean "version 3
   or any later version", make it `GPL-3.0-or-later`. It has to match the
   source.
5. **Release notes.** Every release needs a `<release>` entry in the metainfo
   with 2 or 3 sentences of what changed (no "bug fixes and improvements").

## What the manifest has to cover

You write the manifest; these are the facts about this app that it has to
deal with, so you know what to look up.

- **Built from source.** Flathub builds open-source apps from source, with no
  network during the build, and the pull request may not contain binaries.
  For a Flutter app that means the Flutter SDK and every pub package as
  declared sources. The community tool
  [flatpak-flutter](https://github.com/TheAppgineer/flatpak-flutter) generates
  those source lists from `pubspec.lock`.
- **Native pieces the build downloads today**, each of which must become a
  declared source or a module built from source:
  - CEF (Chromium) for the Linux browser: `third_party/webview_cef` fetches a
    prebuilt CEF 149. Prebuilt binaries are only allowed for "well-known
    vendors on a case-by-case basis": ask the reviewers early, or build CEF
    from source (very heavy).
  - libmpv for the player (`media_kit`): mpv is not in the Freedesktop
    runtime, so build mpv (and libplacebo) as modules; Flathub has many apps
    that do and their manifests show how.
  - The torrent engine and the other native libraries the Linux build links
    (see `scripts/linux_build_deps.sh` and `scripts/package_linux.sh`).
- **Things the app downloads while running.** On Linux the app fetches
  yt-dlp and FFmpeg on first start. Reviewers may ask about this. FFmpeg can
  come from the runtime's `org.freedesktop.Platform.ffmpeg-full` extension
  instead.
- **Chromium's sandbox.** Chromium cannot create its own sandbox inside a
  Flatpak; Chromium-based apps on Flathub use zypak
  (`org.electronjs.Electron2.BaseApp`) or run CEF without its sandbox. Check
  what `third_party/webview_cef` starts CEF with.
- **Architectures.** Flathub builds x86_64 and aarch64. If only x86_64 works,
  add a `flathub.json` next to the manifest that limits the build to it.
- **Runtime.** It must be the newest version on Flathub when you submit
  (org.freedesktop.Platform or org.gnome.Platform; see flathub.org). An
  end-of-life runtime is refused.
- **Permissions.** Keep them minimal and explain each in the pull request.
  What this app plausibly needs: network (downloads, browser, torrents,
  casting); Wayland with X11 fallback and IPC (the window); the GPU (video);
  PulseAudio (sound); the music, videos and downloads folders (where it saves).
  Opening and saving other files should go through the file-chooser portal
  rather than broad filesystem access.

## Submitting

1. Build and run it locally, with Flathub's own builder:

   ```bash
   flatpak install -y flathub org.flatpak.Builder
   ```

   ```bash
   flatpak run --command=flathub-build org.flatpak.Builder --install io.github.Lukas_Bohez.ConvertTheSpireFlutter.yml
   ```

   ```bash
   flatpak run io.github.Lukas_Bohez.ConvertTheSpireFlutter
   ```

2. Lint the manifest and the build:

   ```bash
   flatpak run --command=flatpak-builder-lint org.flatpak.Builder manifest io.github.Lukas_Bohez.ConvertTheSpireFlutter.yml
   ```

   ```bash
   flatpak run --command=flatpak-builder-lint org.flatpak.Builder repo repo
   ```

3. Fork <https://github.com/flathub/flathub> with **"Copy the master branch
   only" unticked**, then:

   ```bash
   git clone --branch=new-pr git@github.com:Lukas-Bohez/flathub.git
   ```

   ```bash
   cd flathub && git checkout -b add-convert-the-spire new-pr
   ```

   Add the manifest (at the top level, named after the id), `flathub.json`
   if needed, and any generated source lists or patches. Not the metainfo,
   desktop file or icon: the manifest takes those from this repository.
4. Commit, push and open the pull request **against the `new-pr` branch**
   (not `master`), titled `Add io.github.Lukas_Bohez.ConvertTheSpireFlutter`.
   In it, explain the permissions and disclose the AI-generated parts (see
   the top of this page). Write the text yourself.
5. When the reviewers' comments are dealt with, comment `bot, build` on the
   pull request for a test build.
6. Once accepted, Flathub creates `flathub/io.github.Lukas_Bohez.ConvertTheSpireFlutter`
   and gives you access; new releases are pull requests there. Sign in on
   flathub.org with GitHub to verify the app, so it shows as verified.
