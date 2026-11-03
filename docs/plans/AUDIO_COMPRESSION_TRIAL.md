# Karoo audio compression comparison

Authorised 2 November 2026: create and run the proposed short-sample comparison.

Goal: compare storage and listening quality before selecting an episode format.

Scope: three 60-second excerpts from the existing fixed Karoo MP3: opening at
00:00:00, scientific discussion at 00:54:50, and closing at 01:48:00. Produce a
lossless reference to the decoded MP3 and HE-AAC 24/32 kbps plus Opus 16/24 kbps
versions. The source is already mono. Each candidate starts from the same PCM
excerpt, rather than from another candidate. Keep the episode source, app,
transcript assets, calibration and edit journals unchanged.

Tasks: record source checksum, tool versions and commands; encode using Apple's
HE-AAC encoder and FFmpeg/libopus; probe and decode outputs; record actual sizes,
projected full-episode sizes and decoder duration differences; supply a local
comparison page and listening instructions. Keep intermediate PCM in work/ and
deliverables in outputs/audio-compression-trial/.

Acceptance: 15 playable comparison files, a reproducible zsh launcher, provenance,
and reports. All files must decode with FFmpeg; independently try Apple's decoder
and report its results. Confirm profile/mono with Apple's afinfo for HE-AAC,
because FFmpeg's interpretation of implicit SBR can differ. Measure durations
without claiming that they establish acoustic alignment or Flutter seek accuracy.

Done when the samples and measured evidence are available. Listening quality and
Flutter/macOS/iOS playback/seek acceptance remain for the listener; selecting a
default, changing the app's audio edition, full-episode encoding, re-alignment and
deleting originals are outside this trial. Media encoding/probing/decoding is
authorised; no Flutter analysis, tests, builds, app launches or Git mutations.

Execution complete: 15 samples created. All decode through FFmpeg and Apple;
native output is exactly 60 seconds each. Sample-based episode projections are
19.6/25.9 MiB for HE-AAC 24/32 and 13.3/19.4 MiB for Opus 16/24, versus 89.1 MiB
currently. Apple's implicit-SBR metadata yields different FFmpeg durations/channel
reporting; native mono/priming checks passed and the discrepancy is documented.
Evidence and listening page: outputs/audio-compression-trial/. Listening quality,
Flutter/AVPlayer seeks and iOS acceptance remain pending; no default selected.
