# Episode package architecture — Karoo first

Authorised 2 November 2026: implement the class architecture using episode 208.

## Goal and scope

One reusable EpisodePackage instance per catalogue Episode, not a different class
per episode. Reuse Episode/Segment, EpisodeTranscript/TranscriptCue and the
existing correction journal. Keep catalogue browsing lightweight; references to
large resources do not load their contents. Pair transcript timings with a named
audio edition, independent of a publisher's changeable streaming URL.

This increment supplies immutable package/resource models, a repository with an
injectable text loader, a central bundled resource registry containing Karoo, and
integration through the existing playback/transcript facades. Existing MP3 and
alignment remain the active, matching edition. Opus 16 kbps is the selected
target for the subsequent processing step; do not declare an uncreated Opus file
or reuse MP3 identity/calibration for it. No media conversion, original deletion,
bulk migration, downloading or new UI in this increment.

## Tasks

1. Model the aggregate, audio edition and transcript resource references.
2. Use GUID for catalogue/correction identity; a stable package key identifies a
   future per-episode directory. Keep bytes, codec, duration and SHA-256 with the
   playback edition. Keep source hash provenance as metadata, never an original
   download path or original file payload.
3. Centralise Karoo's active audio/transcript registration. Keep existing public
   constants as aliases so journal/test callers remain compatible.
4. Load reviewed text/alignment on demand; reject wrong episode/audio identity,
   duration mismatches and incomplete passage counts. Preserve text, passage IDs,
   original edit timing references and all local journal behaviour.
5. Add focused repository/model regression coverage and architecture/usage notes.

## Acceptance and completion evidence

- Karoo resolves to a typed aggregate with its catalogue segments, fixed audio
  and 1032-passage transcript; playback and transcript use the same registry.
- Resolving a package performs no asset reads. Unknown episodes keep existing
  HTTPS streaming and have no advertised bundled transcript.
- An injected loader can load the Karoo baseline/alignment without Flutter UI.
- Duplicate GUIDs/package keys, mismatched GUID/audio/duration, and incomplete
  transcript coverage are rejected; no native plugin is needed for those tests.
- Correction history is still owned by TranscriptEdits/FileTranscriptEditStore,
  keyed by GUID, with calibration scoped to audio identity. No journal rewrite.
- No original download retained as a package member. The active legacy MP3 is
  still needed for playback; discard it only after a validated Opus replacement.

Done when code, focused tests and documentation are supplied. Flutter analysis,
tests, builds and app launches remain manual under AGENTS.md. Report implementation
and verification separately. No Git mutations.

Implementation complete: the aggregate/resources models, lazy repository and
central Karoo registration are supplied. Existing playback/transcript facades
delegate to that registry; audio identity constants remain compatible. Alignment
application accepts an expected edition duration. Five focused repository tests
are supplied, and all seven affected Dart files were formatted. Tests, analysis,
builds, application launches and native listening checks were not run. The
current MP3, transcript files, journal and all other episode registrations remain
at their existing locations. See docs/EPISODE_PACKAGES.md and
outputs/episode-package-architecture/README.md for usage and completion notes.

## Following increment (not implemented here)

Encode the full captured Karoo source to Opus, align/validate against that exact
file, then publish the completed episode directory/manifest and update the active
registry entry. A future explicit source-redownload maintenance operation stages
outside the package, compares the captured source hash and treats changed audio
as a new candidate edition. Ordinary package loading never redownloads a source.
