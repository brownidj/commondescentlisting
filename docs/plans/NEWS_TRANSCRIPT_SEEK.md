# News item transcript seeking

Goal: an item selected from News must not appear to be playing merely because it
was selected. The episode Play action should seek to a conservative transcript
match when available, using current saved corrections, audio edition and offset.

Scope/tasks: shared corrected-transcript snapshot loader; pure matching rules
limited to the published News window before Main discussion; ignore stop words,
reject duplicate headline signatures, preview lists and competing distant matches.
Label successful results as transcript matches, not verified story boundaries.
No/failed/mismatched/ambiguous transcript falls back to the known section time,
with a visible explanation. Unknown section/item timing never invents a start.
Section control always means section playback; make that explicit in selected-news
context. Remove selection-as-playback highlights; unverified News chapter markers
must not be selected merely from approximate source section time.

Done when code, focused matcher/widget regressions and handover are written and
formatted. No automatic tests/analyze/app launches; David runs targeted checks and
native listening against a real last news item with/without a transcript. Preserve
ongoing transcript-index work and its completion evidence. No Git mutations.

Implementation: episode Play in selected-news context resolves a corrected current
transcript, validates fixed audio identity and seeks to a conservative bounded text
match. Status explicitly labels the estimate; failures explain section fallback.
The separate News section control remains a section action. News cards no longer
use navigation selection as playing-style highlights; generic News chapter chips
are never highlighted as item-playing indicators. No autoplay merely from opening
a listing item. Added matcher/widget coverage and updated existing playback test.
Extracted shared corrected-edition loader for news matching and knowledge indexes.
Dart formatted; tests/analyzer/native listening not run. Implementation complete;
verification pending. See outputs/NEWS_TRANSCRIPT_SEEK.md.

Compiler repair — 3 November 2026: the Play onPressed callback must await its
async action rather than return a Future from an inferred void callback. Replace
the old IndexedTranscript name/alias with the single concrete CurrentTranscript
snapshot type across indexes and fixtures, avoiding old-class versus alias identity
during incremental reload. Update round-trip loader coverage. Format only; David
restarts the running app because hot reload retained the replaced class identity,
then runs targeted tests/analyze. No data/schema changes or app launch by assistant.
