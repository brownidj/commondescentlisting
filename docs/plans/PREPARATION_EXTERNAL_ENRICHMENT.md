# External enrichment in episode preparation

Implement the remaining workflow work authorised by David, 4 November 2026.

Goal: share the existing exact-match/apply policy between the one-off rollout and
per-episode preparation. The reusable ZSH entry accepts package, edition, sidecar
and output paths. All five categories remain distinct. No transcript/audio edits,
new models, paid lookups, Git mutations or dependency installation.

The standalone route enriches after indexing, before registration/reporting.
The app worker runs external enrichment before optional ChatGPT fallback, then
validates/activates the final sidecar. Only unconfirmed suggestions are sent to
ChatGPT; external confirmation is stored separately from human review. Enrichment-only retry bypasses acquisition,
recognition, alignment and ChatGPT. Retry works on a staged index and commits only
when the selected edition and original sidecar hashes still match.

Checkpoint identity includes package/baseline hashes, edition, input/output index
and summary hashes, source configuration and policy/parser code hashes. Persist
per-entity resolutions to resume interrupted lookups; retry missing/error sources
explicitly. Protect two-file index/summary publication using a recovery journal,
backups and compare-before-write. Cancellation preserves the prior usable pair.
Default network lookups are bounded and cached; cache-only mode is explicit.
Missing services retain usable local/refined entries and produce visible warnings,
not a failed transcription. Hard unresolved names and stale evidence are separate.

Add worker progress, cancellation, retry operation, final JSON/Markdown reports and
app summary/retry controls. Registration and portable export must use final package
sidecars, not pre-refinement local-index copies. Server export is opt-in/existing
configured destination; do not unexpectedly duplicate all audio on every job.

Acceptance fixtures (manual execution unless separately authorised): shared-policy
exact/ambiguous decisions, source outages/cache-only operation, checkpoint reuse
and invalidation, interrupted lookup reuse, partial-commit recovery/cancellation,
retry without paid/transcription commands, final hash selection in registration
and export, worker/app summary and cancellation handling. No tests/analysis/builds
or applications will be run during implementation. Record commands and outstanding
manual checks in outputs/preparation-enrichment/IMPLEMENTATION.md.

## Implementation status

Shared policy/configuration, per-episode ZSH entry, checkpoints/recovery, standalone
and pre-refinement worker stages, staged enrichment-only retries, UI progress and
warnings, final revision serving/export and report fields are implemented. Added
focused offline fixtures and updated worker/Flutter fixtures. No tests, analyser,
builds or applications run; Dart formatting only. Detailed file list, commands,
manual acceptance and limitations: outputs/preparation-enrichment/IMPLEMENTATION.md.
Status: implementation complete; verification pending.

## Revised order — external confirmation before ChatGPT

David now requests: local index → external enrichment → optional ChatGPT fallback
for unconfirmed entries only → validate/activate/report. This supersedes earlier
ordering in this plan. Keep externally confirmed status separate from human review,
bind it to the current name/category and exact edition/passage evidence, retain its
source attribution across app serialization and show a confirmation indicator.
Do not send confirmed entries to ChatGPT, mutate them through API recommendations,
or require a credential/request when no fallback candidates remain. Uncertain API
responses remain unresolved. Add focused fixtures; no tests/analysis/builds or live
API/preparation runs during implementation.

## Explicit ChatGPT-only retries and transport diagnostics — 4 November 2026

User authorises retrying the Cambrian Explosion refinement and reporting failures.
Use the existing model and US$0.50 per-request ceiling, one new attempt only;
retain earlier request/usage records. Stage from the currently selected index
revision, skip audio/transcription/enrichment, and activate only after a successful
validated result with unchanged edition/source hashes. App retry asks confirmation
that the old request may have incurred usage. No automatic repetition.

Fix the worker Python's missing default CA trust using the installed certifi bundle
with certificate and hostname verification still enabled. Record sanitized error
category, exception class, errno/TLS verification code, request phase, elapsed time,
client request ID and server request ID. Do not log keys, raw server messages or
transcript data in errors. Surface diagnostics in preparation results/dialogs.

Acceptance: TLS verification remains enabled; failure leaves active revision
unchanged; successful manual retry updates final revision/export and records
returned usage; retry bypasses model/audio work; no marker is deleted/reset; error
categories distinguish certificate, DNS, timeout, reset and HTTP errors. Add focused
fixtures; leave test/analyzer/build/app checks to David. Live diagnostic and the
explicitly authorised paid retry are work actions, not automated test execution.

Live retry result: verified-HTTPS read-only diagnostic succeeded after adding the
installed trust bundle. One paid review returned 163/242 rows. Saved-response
recovery (no second request) applied 155 supported decisions, holding 79 missing,
2 unsupported and 6 low-confidence results. Partial review is now an explicit
state, with per-candidate evidence scope and provenance; completed valid decisions
are skipped on later retries until metadata/evidence changes. A manual retry action
is available both after a job and when opening preparation for an existing episode.
The old failure logs and request markers remain preserved. Cost estimate from
returned usage and configured model rates: US$0.045846. No automated checks run.
