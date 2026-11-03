# Karoo Opus episode package

Authorised 2 November 2026 as the next step after the package class architecture.

Goal: publish Karoo's retained Opus recording at a 16 kbps target with new
full-episode acoustic timing, and make it the registered audio/transcript pair.

Scope: reuse the captured source edition (do not fetch potentially different
advertising). Encode once with libopus, mono, constrained VBR, audio mode. Check
Apple media-container support before selecting the final container; remuxing is
allowed without another lossy encode. Finalise the recording before hashing and
running WhisperX against its decoded audio. Reuse reviewed text and listener
corrections as alignment input; retain baseline text/IDs and original edit timing
references so the existing listener journal remains compatible.

Tasks: create a repeatable zsh processing launcher; record source/baseline/journal
hash provenance, encoder settings and decoder evidence; run full WhisperX with
neighbouring passage context and boundary reconciliation; generate reviewed
baseline, timing/word alignment, TXT/VTT/SRT exports, canonical segment snapshot
and an episode manifest in a single stable-key episode directory. Register that
pair through BundledEpisodePackages and pubspec, and update affected regressions.

Acceptance: all 1032 IDs retained; positive, ordered, bounded passage timings;
alignment identity matches final compressed bytes; no source download inside the
package; no original/journal deletion or rewriting. New audio identity starts
with its own calibration; old edition offsets remain recoverable. Unknown
episodes keep streaming. Package manifest records declared resources, hashes,
source provenance, processing method and review flags. The original MP3 stays on
disk until native playback/seeking and listener acceptance pass; remove its
pubspec registration so it is no longer included in newly built apps.

Execution of media encoding, decoding, alignment and publication integrity checks
is authorised by this request. Headless native media inspection is part of that
processing, not a Flutter build or application launch. Flutter tests, analysis,
builds and product launches retain the project's manual default. No Git changes.

Done when processing has run, the episode directory/manifest and integrated
registration are supplied, and evidence/limitations are reported. Machine
alignment is not human listening verification. Native iOS/macOS user acceptance
must be recorded separately before disposing of source bytes. A general
redownload command and bulk catalogue migration are separate increments.

Implementation/execution complete: final Opus SHA-256 is
b1d4fc7089dda6b9c1f5f42b8887ddc267a4305b47da0fab95f2507bcc6ee38d;
13,954,279 bytes, 85.1% smaller than the source. Apple and FFmpeg decoded identical
sample counts (104,696,150 at 16 kHz); native macOS marked it playable and seven
paused precise seeks completed at requested positions. WhisperX ran in 304.262
seconds: 1032/1032 passages, five joint boundary realignments, no remaining
overlaps, missing passage timings or automatic timing-review flags. Human
accuracy/listening remains unverified. Nine local corrections were alignment
input/exported, and the installed journal and original baseline were unchanged.

The 17.1 MiB episode directory is published under flutter_app/assets/episodes/
870afb21-277f-398e-ba55-6e50d68ceda6/. Manifest checksums cover its 10 artifacts.
The active registry/pubspec now use this Opus pair. Manifest parsing and stale
registration checks were added; regression coverage updated for Opus and
independent MP3 calibration. Existing MP3 remains on disk, is ignored by Git, and
is no longer bundled. Regenerable PCM was cleaned up. No source redownload or
deletion. Dart files formatted; Flutter tests/analysis/builds/product launches
and iOS checks were not run. See outputs/karoo-opus-package/README.md.
