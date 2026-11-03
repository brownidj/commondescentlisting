# Karoo API indexing trial

Authorised 3 November 2026: prepare and run one-episode contextual extraction,
validate passage evidence, compare with an independently reviewed sample, and
report actual API usage plus calculated cost. Trial outputs remain separate from
accepted app indexes; no production registry changes or automatic bulk processing.

Tasks: snapshot active Karoo edition/alignment and only matching correction journal;
retain original wording, IDs, audio identity and existing times. Manually annotate
fixed sample ranges before API output is viewed. Extract fossils/groups, places /
geological units, authors and explicitly mentioned references in overlapping
chunks using strict JSON schema; require verbatim quotes/valid passage IDs. Preserve
spoken and proposed normalized names separately. Missing publication metadata stays
null. Deduplicate exact normalized entity/type/subtype keys only; don't merge broad
groups into species. Save requests/responses/usage/model/prompt/schema/source hashes,
validation failures, per-request cost calculation and a reviewable report. Cache
completed responses and refuse changed input on resume. Bound request count/output
and projected spend. API key only from environment or ignored mode-600 work file;
never output request authorization or credential-bearing errors.

Acceptance: evidence validation passes before entries enter proposal output; times
come from source only. Sample comparison distinguishes naming, missed entities,
false positives, references and unsupported normalization. Record actual successful
requests and usage; calculated cost is not an invoice. If credentials/billing/model
access block running, preserve prepared work and report the exact limitation rather
than fabricating API results. The authorised trial includes running its extraction
and evidence checks; do not run unrelated Flutter/tests/builds/app launches or Git.

Follow-up authorised 3 November 2026: replace all placeholder reference headings with known author/date/subject labels; research reliable bibliographic details and correct the trial index. Preserve raw API output and transcript quotations. Store editorial labels, source URLs and precision of publication dates separately from transcript-derived metadata, retaining uncertainty about publication identity. Regenerate the offline review and consolidated trial index without further paid API calls or app index changes. Acceptance: no placeholder paper/article headings; exact requested du Toit example; original IDs, occurrences and timings unchanged; additions traceable to sources.
