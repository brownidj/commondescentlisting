# WhisperX alignment trial

Authorised 2 November 2026: run a short Karoo trial, keeping listener data intact.

Goal: align reviewed passage text to a captured audio clip; determine whether
word-level timestamps improve the original machine-generated passage boundaries.
Scope: first 120 seconds, WhisperX 3.8.6 CPU alignment only, isolated environment,
ZSH launcher calling the package's Python library API (its CLI retranscribes).
No retranscription, Flutter changes, journal edits or installation into the app.

Tasks: confirm Nudge persists; capture and fingerprint clip; preserve reviewed
text and passage IDs; align in padded approximate passage windows; save raw word
results, original/new timing comparison, scores and review flags. Preserve local
corrections in the trial text where applicable. Pin dependencies and record runtime.

Acceptance: successful actual alignment run; unchanged listener asset and journal;
explicit clock basis, audio fingerprint and mapping of output to original IDs;
failed/low-score results flagged rather than silently adopted. Preserve evidence
of any difference between this captured audio and the listener's advertised stream.

Done when run outputs and a candid result report are saved in outputs/whisperx-trial.
Manual listening remains necessary before adopting timestamps. This request
authorises the WhisperX trial execution; unrelated Flutter tests/builds remain
manual. Nudge already uses the atomic persisted transcript offset save path.

Completed trial: 32 passages in a 120-second clip. Independent padded-window
alignment produced 26 flagged passages, so a second run aligned consecutive text
in <=30-second chunks and mapped words back by exact sequence. It completed with
6 flagged passages at chunk boundaries. Preserve and review these; do not clamp
or automatically adopt. The saved clip matches the original decoded audio exactly,
not the listener's longer advertised stream. See outputs/whisperx-trial/RESULTS.md.

Nudge persistence: read the installed journal at -30,501 ms, matching one 500 ms
step from the prior -31,001 ms setting with nine text revisions intact. Strengthened
the existing file-store round-trip test to cover both nudge directions and a new
store instance. This Flutter test was not run; no production save changes needed.
