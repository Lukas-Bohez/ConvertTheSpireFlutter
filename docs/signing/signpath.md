# Code signing with the SignPath Foundation

The project has applied to the [SignPath Foundation](https://signpath.org/)
for free code signing of the Windows downloads. The release workflow
(`.github/workflows/release.yml`) is ready for it: signing switches on as soon
as the repository variable `SIGNPATH_ORGANIZATION_ID` exists. Until then
releases are built exactly as before, unsigned.

## What gets signed

| File | Signed | Why |
|---|---|---|
| `convert_the_spire_reborn.exe`, the app | Yes | Signed right after the build, so the Windows zip and Setup.exe both contain the signed exe. |
| `ConvertTheSpireReborn-Setup.exe`, the installer | Yes | The file people download and double-click. |
| The DLLs next to the exe (`dll\`) | No | Flutter's engine and the plugins are other projects' files. SignPath's terms allow shipping upstream binaries unsigned; they are never signed with this project's certificate. |
| `unins000.exe`, the uninstaller | No | Inno Setup writes it when installing. It never comes from the internet, so Windows does not check it. |

Every signed file carries the product name **Convert the Spire Reborn**:
`windows/runner/Runner.rc` for the exe, `windows/installer/ConvertTheSpireReborn.iss`
for Setup.exe. The artifact configuration below only signs files with that
name, so nothing else can be signed by mistake.

`tools/check_windows_metadata.ps1` checks the product name and version of both
files on every pull request (CI) and before each release asks for signing, so
a wrong name fails the build rather than the signing request. It also makes
sure the app's `CompanyName` stays `Oroka Conner`: path_provider builds the
Windows data folder from it, so changing it would lose everyone's settings and
library.

Each release asks for approval twice, once for the exe and once for
Setup.exe, because the installer is built from the signed exe.

## Once the application is approved

### In SignPath (app.signpath.io)

1. **Project.** The SignPath Foundation sets it up. Note the project slug and
   your organization ID (Settings > Organization). The workflow assumes the
   slug `ConvertTheSpireFlutter`; if it is different, set the variable below.
2. **Artifact configuration.** Add this one and make it the project's
   default. Each signing request is a zip (GitHub puts every artifact in one)
   with a single exe in it:

   ```xml
   <?xml version="1.0" encoding="utf-8"?>
   <artifact-configuration xmlns="http://signpath.io/artifact-configuration/v1">
     <zip-file>
       <pe-file path="*.exe" product-name="Convert the Spire Reborn">
         <authenticode-sign/>
       </pe-file>
     </zip-file>
   </artifact-configuration>
   ```

3. **Signing policy.** `release-signing`, with you as approver. The workflow
   assumes that slug; if it is different, set the variable below.
4. **Trusted build system.** Link GitHub.com to the project and install the
   SignPath GitHub App on this repository, so SignPath can check that each
   file was built by this repository's release workflow on GitHub's runners.
5. **CI user.** Create one, make it a submitter on the signing policy, and
   copy its API token.

### In GitHub (Settings > Secrets and variables > Actions)

| Name | Kind | Value |
|---|---|---|
| `SIGNPATH_API_TOKEN` | Secret | The CI user's API token |
| `SIGNPATH_ORGANIZATION_ID` | Variable | Your SignPath organization ID. Setting it switches signing on. |
| `SIGNPATH_PROJECT_SLUG` | Variable, only if not `ConvertTheSpireFlutter` | The project slug |
| `SIGNPATH_SIGNING_POLICY_SLUG` | Variable, only if not `release-signing` | The signing policy slug |

### Releasing

Run the release workflow as always. The Windows job stops twice and waits
up to an hour each time for you to approve the signing request in SignPath
(it emails you): first the exe, then Setup.exe. The workflow checks that each
file came back signed before it is used.

The release page then says the downloads are signed. Its text about
"Windows protected your PC" changes too: a new certificate still has to
build up reputation with Windows, so the warning can show for a new version
until enough people have downloaded it.

One thing to watch on the first signed release: Inno Setup pads the file
details in Setup.exe with trailing spaces (the metadata check prints them in
brackets, and trims them before comparing). If SignPath rejects the Setup.exe
request over its product name, the padding is the cause: ask the SignPath
Foundation whether their check trims, or match Setup.exe by file name
(`path="ConvertTheSpireReborn-Setup.exe"`, without `product-name`) in the
artifact configuration.

After the first signed release, update the Code signing policy section of
`README.md`: remove the sentence saying the downloads are not signed yet.
