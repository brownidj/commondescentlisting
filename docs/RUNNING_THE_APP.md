# Running CD List

Updated 9 November 2026. The app is named **CD List**; its project folder is **CD List**. These instructions describe the current project on David's Mac. All Terminal commands use **zsh**.

## Quick start on macOS

Open Terminal, or the Terminal panel in PyCharm, and run:

```zsh
cd '/Users/david/Library/Mobile Documents/com~apple~CloudDocs/PyCharm projects/CD List/flutter_app'
export PATH="/Users/david/development/flutter/bin:$PATH"
flutter pub get
flutter run -d macos
```

The first command selects the Flutter app inside the project. The PATH setting makes the installed Flutter SDK available in this Terminal session. `flutter pub get` installs the app's Dart dependencies; `flutter run` builds and launches the macOS debug app.

Keep this Terminal session open while using `flutter run`. Press `r` for hot reload, `R` for hot restart, or `q` to stop the app. Quit an already running copy with **Command–Q** before starting another build.

You do **not** need to activate the project's Python `.venv` to launch Flutter. Flutter and Xcode must already be installed and configured. To inspect their setup or see available devices:

```zsh
flutter doctor -v
flutter devices
```

## Automatic catalogue updates

On every fresh app launch, CD List first reads its saved catalogue (or the bundled
copy), then checks for an update. With a library server configured, it refreshes
that server's published catalogue; otherwise it fetches the official Common Descent
RSS feed. A progress bar and stage message appear during the check/download/save.
The feed request has a 35-second deadline. Unknown download sizes use an animated
bar rather than an invented percentage.

Updates are validated and saved for later offline launches. Older episodes absent
from a limited RSS response are retained. If the network/server is unavailable or
an update is invalid, the app keeps its existing catalogue and shows a notice.
This downloads catalogue metadata only; preparing transcripts and downloading audio
remain separate operations. The author's project YAML and server export are not
rewritten by a listener's app. A configured server needs a refreshed export to
publish new episodes. Use a full app restart, rather than hot reload, to trigger
another startup check.

## Which services need to be running?

| What you want to do | What to start |
| --- | --- |
| Browse bundled episodes, news and indexes | The Flutter app only |
| Use bundled transcripts and packaged audio | The Flutter app only |
| Prepare new transcripts, create transcript PDFs on the Mac, or access editions served by the preparation worker | The Flutter app and the preparation worker |
| Stream audio, transcripts and indexes from an exported central library | The Flutter app and the library server |

The two servers are separate. The preparation worker uses port **8765**; the read-only library server uses port **8766**. Neither is needed just to browse the bundled catalogue. Online episode pages, remote audio, model downloads, external enrichment and ChatGPT requests need network access.

## Start the preparation worker

Open a **second Terminal tab/window** and run:

```zsh
cd '/Users/david/Library/Mobile Documents/com~apple~CloudDocs/PyCharm projects/CD List'
zsh scripts/episode_preparation_server.zsh
```

Leave that Terminal open. This uses the existing processing environment at `work/whisperx-trial/venv/`, together with whisper.cpp, ffmpeg, WhisperX and the local indexing dependencies. Activating the ordinary project `.venv` does not replace that environment. If the worker reports a missing dependency, retain its error message rather than starting repeated copies.

To connect for the first time:

1. In the app, select an episode and press **Prepare transcript**.
2. Choose **Choose project folder** when prompted.
3. Select this folder, **not** its `flutter_app` subfolder:

   ```text
   /Users/david/Library/Mobile Documents/com~apple~CloudDocs/PyCharm projects/CD List
   ```

4. Choose the transcription **Model**; the default for a new episode is **medium.en**. Missing supported models are downloaded when selected.
5. Check **Refine using ChatGPT**. It is **on by default** and can incur API charges, with the current US$0.50 per-job guard. Turn it off to avoid a paid ChatGPT request. The API key is configured on the Mac using `zsh scripts/configure_indexing_key.zsh` from the project root; do not enter it in Flutter settings.
6. Review the processing estimate and start preparation.

An already prepared episode offers re-preparation choices, including redownloading its recording or using a larger transcription model. The workflow encodes the retained audio, transcribes and aligns it, indexes locally, enriches from external sources, then optionally asks ChatGPT to resolve remaining suggestions. Validation precedes activation; an unsuccessful replacement retains the previous edition.

Progress shows the current stage, elapsed time and estimates. **Continue in background** closes the dialog while processing continues. Use **Preparation progress** in the main toolbar/banner to reopen it. Successful worker-prepared editions become available without rebuilding the app.

Only one worker and one preparation job should run at a time. **Ctrl–C in the worker Terminal stops the worker and its active work.** To update worker code, allow the job to finish or cancel it in the app, stop the worker with Ctrl–C, then run the same launch command again. Restart the app after updating its native code or plugins.

Detailed preparation notes: [IN_APP_EPISODE_PREPARATION.md](IN_APP_EPISODE_PREPARATION.md). Some older labels in that document predate the current **Prepare transcript** button.

## Choose the audio player and open a transcript

Use the main page's **Settings** cog and choose **Audio player** for playback inside CD List, including passage and segment seeking. Choose **Apple Podcasts** to open episodes in Apple's app; transcript passage seeking is provided by the in-app player.

Select an episode, press its **Play** icon, and use **Transcript** when available. The small transcript indicator in episode listings identifies prepared episodes. Transcript mode includes search, playback highlighting and correction tools. **Create .pdf** creates a text-only PDF with paragraphs and single line spacing in `docs/transcripts/`, using the preparation worker on macOS.

## Run without a Flutter Terminal session

To build an app that can be opened directly, quit the running copy, then run:

```zsh
cd '/Users/david/Library/Mobile Documents/com~apple~CloudDocs/PyCharm projects/CD List/flutter_app'
export PATH="/Users/david/development/flutter/bin:$PATH"
flutter pub get
flutter build macos --release
open 'build/macos/Build/Products/Release/CD List.app'
```

After building, open that `.app` in Finder on subsequent occasions. It does not require `flutter run` to remain open. Start the preparation worker or library server separately when their features are needed.

For a debug build, use `flutter build macos --debug` and open `build/macos/Build/Products/Debug/CD List.app`. Avoid keeping different Debug and Release copies running. Native icon or plugin changes require a rebuild and full quit/relaunch; hot reload does not update them.

## Optional: use the central library server

For an existing server, open **Settings → Central library**, enter its **Server address** and **Read token**, then press **Connect**. Use **Refresh library** after the server publishes an updated library. This connection serves audio, transcripts and indexes read-only; it does not run transcription jobs or provide an offline audio download cache.

To host the library on this Mac, export the completed editions from the project root:

```zsh
cd '/Users/david/Library/Mobile Documents/com~apple~CloudDocs/PyCharm projects/CD List'
zsh scripts/export_library.zsh
```

Create a read token **once**, if that file does not already exist:

```zsh
zsh scripts/create_library_token.zsh "$PWD/work/library-server/read-token"
```

Start the server in its own Terminal:

```zsh
zsh scripts/library_server.zsh --library "$PWD/outputs/library-server/library" --token-file "$PWD/work/library-server/read-token"
```

Use `http://localhost:8766` in the app on this Mac. Copy the token from `work/library-server/read-token` into **Read token** and keep it private. Leave the server Terminal open; Ctrl–C stops it. Re-run the export after preparing more episodes, then refresh the library in the app.

The default server accepts connections only from this Mac. To serve another device on the same trusted network, add `--host 0.0.0.0` to the server command and enter this Mac's actual network hostname or IP address in the client, for example `http://library-mac.local:8766`. `localhost` on an iPhone means the iPhone itself. Local network/firewall permission may be required. This HTTP prototype is intended for a trusted local network, not public Internet exposure.

Architecture and transfer notes: [CENTRAL_LIBRARY_SERVER.md](plans/CENTRAL_LIBRARY_SERVER.md).

## Install on the iPhone for repeated use

Use a **release build** so CD List can be reopened from the Home Screen without
a Flutter/debugger session. Unlock the paired phone, make it available to Xcode,
and keep the existing signing configuration. From zsh:

```zsh
cd '/Users/david/Library/Mobile Documents/com~apple~CloudDocs/PyCharm projects/CD List'
export PATH="/Users/david/development/flutter/bin:$PATH"
zsh scripts/run_ios_release.zsh
```

This configures Flutter for release, builds with Xcode in a local cache outside
iCloud Drive, installs and launches the release app. It avoids the ordinary
Flutter build route that has returned Xcode status 255 on this Mac. The launcher
successfully built, installed and launched CD List on David's phone on
9 November 2026. From `flutter_app/`, the same command is
`zsh ../scripts/run_ios_release.zsh`.

Afterwards, tap **CD List**
on the phone's Home Screen whenever you want to use it, including after restarting
the phone. You do not need to repeat the command for every launch, keep Terminal
open, or connect the phone to the Mac for ordinary use. Installing from the current
source applies the CD List name and current icon.

Run the launcher again when you want to install updated code, naming or artwork.
Update the existing installation rather than uninstalling it, to retain saved app
data. A development-signed installation may also need rebuilding/reinstalling if
its signing profile needs renewal.

Enable Developer Mode if requested. If installation succeeds but launch is denied
because the phone is locked, unlock it and open the installed app from the Home
Screen; a launch denial alone does not mean installation failed.

The preparation tools run on the Mac; they do not execute locally on iOS.
Server-hosted audio, transcripts and indexes still require a reachable central
library server. Start that server on the Mac and connect using its network
address and read token; the release build does not copy that entire library onto
the phone.

For signing details and the Xcode fallback, see [IOS_DEVICE_RUN.md](IOS_DEVICE_RUN.md).

Each launcher run saves configuration/build/install/launch logs under
`outputs/ios-release/<run>/`. A failure prints its stage and full log path. If the
phone is locked after a successful installation, the launcher reports that
separately and leaves the installed app ready to open after unlocking.

## Common startup problems

| Symptom | What to do |
| --- | --- |
| `flutter: command not found` | Run the PATH command above in the same Terminal, or use `/Users/david/development/flutter/bin/flutter` directly. |
| `Failed to foreground app; open returned 1` after a successful macOS build | Open `build/macos/Build/Products/Debug/CD List.app` from `flutter_app/`. Check for an existing running copy first. |
| Cannot connect to preparation, or prepared media is unavailable | Start the worker; on first connection choose the project root. Keep its Terminal running. |
| `A preparation worker is already running` | Use the existing worker Terminal. Do not launch another instance or remove locks to bypass an active job. |
| Cannot connect to the central library | Check the server process, address, port and read token. Use the Mac's network address from a different device. |
| Xcode fails with exit code `-9`, or another native build error | Keep the complete first error. Quit duplicate app/build sessions, inspect Xcode's build output and available memory, then retry once the cause is addressed. The message alone does not identify the cause. |
| iOS `flutter run` reports Xcode status `255` | Use `zsh scripts/run_ios_release.zsh` from the project root. It uses the verified direct Xcode route and a local cache outside iCloud. Inspect the printed stage log if it fails. |
| Old icon or native behavior after an update | Fully quit the app, rebuild, and open the exact Debug or Release bundle just built. |

Do not delete saved packages, correction journals or checkpoints as a general startup remedy.

## Where files are stored

| Location, relative to the project root | Purpose |
| --- | --- |
| `flutter_app/` | Flutter project; run Flutter commands here |
| `data/segments.yaml` | Canonical generated episode/news catalogue |
| `flutter_app/assets/data/segments.yaml` | Bundled catalogue snapshot |
| `work/episode-preparation/` | Worker connection, job state and active local packages |
| `outputs/episodes/<key>/runs/<job-id>/` | Processing logs, reports and generated episode outputs |
| `docs/transcripts/` | Listener transcript copies and generated PDFs |
| `outputs/library-server/library/` | Exported central library |

The app also stores preferences, imported catalogue data and listener corrections in its macOS Application Support area. Use the app's controls to manage these rather than editing private storage directly.

## Optional checks after changing the app

From `flutter_app/`, run:

```zsh
flutter analyze
flutter test
```

These checks are separate from launching the app. This guide was checked against project source and existing documentation; creating it did not run builds, tests, services or API requests.

## Transcription on mobile

iOS and Android display existing transcripts but cannot prepare new ones. Episode
pages ask you to use a desktop or laptop for transcription. Prepare the transcript
on the Mac, then make the completed edition available to the phone through your
library server or an updated app bundle.
