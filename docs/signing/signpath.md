# Windows code signing (SignPath Foundation)

The project has applied to the [SignPath Foundation](https://signpath.org/) for
free code signing. Until the application is approved, the signing steps in
`.github/workflows/release.yml` are skipped and the Windows downloads ship
unsigned, as before.

## What gets signed

- `convert_the_spire_reborn.exe`, built by the release workflow from this
  repository. It is signed before the zip and `Setup.exe` are made, so both
  carry the signed exe.
- `ConvertTheSpireReborn-Setup.exe`, the Inno Setup installer the release
  workflow builds.

Nothing else is signed: `flutter_windows.dll` and the plugin DLLs come from
upstream projects, yt-dlp and FFmpeg are downloaded from their own releases at
run time, and Inno Setup's uninstaller (`unins000.exe`) can only be signed with
a local SignTool while the installer is compiled. Android and macOS are signed
separately and are not part of this.

Each file's product name and version must match what the signing request says
(the artifact configurations below). `tools/check_windows_metadata.ps1` checks
them on every pull request (CI) and before every release is sent for signing.
It also makes sure the app's `CompanyName` stays `Oroka Conner`: path_provider
builds the Windows data folder from it, so changing it would lose everyone's
settings and library.

## Once the application is approved

In SignPath (app.signpath.io), for the project SignPath Foundation creates:

1. **Artifact configurations:** create `windows-app` from
   [`signpath-windows-app.xml`](signpath-windows-app.xml) and
   `windows-installer` from
   [`signpath-windows-installer.xml`](signpath-windows-installer.xml).
2. **Signing policy** `release-signing`, with the approver (Lukas-Bohez)
   approving every request by hand, and GitHub.com as its trusted build
   system.
3. **A CI user** with submitter rights on that policy, and an API token for it.
4. **Multi-factor authentication** on SignPath and on GitHub, for every team
   member. SignPath Foundation requires it.

In this repository, under Settings, Secrets and variables, Actions:

| Kind | Name | Value |
|---|---|---|
| Secret | `SIGNPATH_API_TOKEN` | the CI user's API token |
| Variable | `SIGNPATH_ORGANIZATION_ID` | the organization ID |
| Variable | `SIGNPATH_PROJECT_SLUG` | the project slug |

Setting `SIGNPATH_ORGANIZATION_ID` is what switches signing on.

## Every release

Run **Release Build** as usual. The Windows job stops twice and waits for you
to approve a signing request in SignPath: first the app, then the installer.
Each waits up to 90 minutes, and the job fails if a request is not approved or
a file comes back without a valid signature.

## After the first signed release

Change "will get free code signing" to the present tense, and drop "the Windows
downloads are not signed yet", in:

- `README.md` (Code signing policy),
- `docs/releases/release_body_template.md`,
- quizthespire.com/tools/convert (Code signing policy, and the SmartScreen
  answer in the FAQ).

The required sentence is: *Free code signing provided by SignPath.io,
certificate by SignPath Foundation.*
