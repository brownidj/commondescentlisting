# Episode package class architecture — completion notes

2 November 2026. Implementation complete; verification pending. Unphased work.

## Delivered

EpisodePackage is an aggregate over the existing Episode/Segment model and optional
EpisodePackageResources. EpisodeAudioEdition owns recording identity/codec/size/
duration; EpisodeTranscriptAssets contains lazy baseline/alignment references.
EpisodePackageRepository resolves lightweight instances and loads transcripts on
demand. Karoo is registered once in BundledEpisodePackages, shared by the legacy
EpisodeAudio and BundledTranscripts facades. The repository requires the transcript
to match the active audio identity, exact alignment duration and passage count.

This supplies the first live example using the current MP3/alignment pair. It
does not manufacture a full Opus recording or declare that old timings have been
validated against one. No original-download file/path is a package field; a source
checksum can be kept as metadata. The current MP3 remains required for playback.

Correction storage, IDs, original cue revision references and calibration identity
are unchanged. Unknown episodes retain HTTPS streaming and no bundled transcript.
No media was encoded, moved or deleted in this increment, no journal was rewritten,
and no Git mutations occurred. Physical per-episode storage/manifests, source
redownload and full Opus processing are the following increments.

## Created files

Paths below are relative to the CommonDescentListing project root.

- `flutter_app/lib/models/episode_package.dart`
- `flutter_app/lib/data/episode_package_repository.dart`
- `flutter_app/lib/data/bundled_episode_packages.dart`
- `flutter_app/test/data/episode_package_repository_test.dart`
- `docs/EPISODE_PACKAGES.md`
- `docs/plans/EPISODE_PACKAGE_ARCHITECTURE.md`
- `outputs/episode-package-architecture/README.md` (this report)

## Modified files

- `flutter_app/lib/data/episode_audio.dart`: delegates to the package registry;
  retains existing public constant aliases.
- `flutter_app/lib/data/bundled_transcripts.dart`: delegates to the same registry.
- `flutter_app/lib/models/transcript_alignment.dart`: optional expected-duration
  validation, used by the package repository.

No files removed. Existing uncommitted work outside this task was preserved.

## Verification

Completed: Dart formatting on the seven new/modified Dart files and source review.
Tests actually run: **none**. Flutter analysis, tests, builds and app launches were
not run under the project's manual-verification default. No new dependencies.

Five focused tests were added: lazy resolution/streaming fallback; loading the
actual Karoo transcript; GUID/audio identity/duration mismatches; passage coverage
and missing transcripts; registry collisions and cross-episode associations.
Existing aligned-playback regression coverage should also be rerun to check
correction history and edition-scoped calibration.

Run from `flutter_app`, using zsh:

```zsh
flutter analyze
flutter test test/data/episode_package_repository_test.dart test/features/episodes/aligned_playback_test.dart
```

Manual acceptance (not performed by the assistant):

1. Open Karoo, start audio and open its transcript. Confirm the existing fixed
   recording, 1032 passages, saved text corrections and saved Nudge still load.
2. Exercise play, seek and editor replay/resume. Confirm no source change.
3. Open another episode and confirm normal streaming and navigation.

Record environment/date/tester/results when these checks are run. No native
playback/seek quality claim is made by the class refactor. Checksum fields describe
registered assets; publishing/import is responsible for verifying actual bytes.

## Next boundary

Prepare the full Opus 16 kbps edition, align against its final bytes, validate
playback/seeking, and publish an episode directory/manifest. Update the active
audio/transcript pair together. Retire the MP3 only after that replacement passes
acceptance. Explicit source redownload will stage temporary candidates and never
silently overwrite an active episode package.

Suggested commit: `Introduce episode packages with Karoo as the first example`.

## Reported constructor lint

David reported one `prefer_initializing_formals` info in the repository. Changed
the loader to a final `loadText` field with `required this.loadText`, matching the
existing injected-controller convention. The named constructor argument and call
sites remain compatible. Only the repository and this report were modified for
the fix; no tests added/changed. Formatted the repository; analysis/tests were not
run. Rerun the two commands above. Suggested commit: `Fix episode repository
initializing formal lint`. Unphased fix; verification pending.
