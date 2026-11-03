# Transcript library and indexes

Open **Indexes** from the navigation rail or bottom navigation. The Index selector
has Transcripts, Fossils, Places, Papers, Articles and Authors.

## Browsing and search

Names/references support search and A–Z/Z–A order. Search includes preferred name,
aliases, place category, publication and DOI, and publication author names.
Suggested and confirmed entries appear by default; select a review state to see
only that state, including rejected entries. Rejected entries have no derived hits.

Select an entry to see its passages, exact current quotations, episode, passage
number and audio start. Open passage opens the surrounding transcript without
seeking or starting audio. If audio is already playing, the reader holds this
requested passage until Follow audio or a passage play action is pressed.
Play uses the in-app audio setting and matching fixed recording, applies the
latest saved Nudge adjustment and refuses stale transcript editions/text. If
Apple Podcasts is selected, switch to Audio player in Settings to play timed hits.

Transcripts lists only episodes with available transcripts, with publication date,
passage count and the transcript's review label. Sort by date in either direction
or title A–Z/Z–A. Enter a phrase to search passage wording across all transcripts;
Search within can restrict the search to one episode. Results highlight literal
search text. Open a passage to edit it with the existing transcript editor.
Returning refreshes index occurrences from saved corrections.

## Reviewing names and references

Detection is offline and proposes candidates, not authoritative identifications.
A starter vocabulary and conservative name/context patterns find possible fossil
names/groups, places/geological units, explicit author names and reference mentions.
Single surnames and missing titles are not resolved to real-world identities.
There will be false positives and missed names. Review wording before confirming.
Use aliases to collect alternate spellings; keep a broad group separate from a
particular genus (elasmosaurs is not treated as a synonym of Elasmosaurus).

Use + to add a name/reference; select an entry and Review / edit entry to change
its name, aliases, category, notes and suggested/confirmed/rejected state. Rejection
is retained so the same candidate is not repeatedly added on refresh. New place
names can be categorised as geographic location, fossil site or geological unit.

Papers and articles are separate types. Automatically detected references are
labelled Untitled paper/article and show their actual spoken quotation; the app
does not invent a title, journal, publication year, DOI or URL. Literal DOIs remain
unverified. A detector can suggest an author relationship from explicit wording,
but the reference and attribution still require review.

Add shared author records in Authors, then select them in a paper/article's editor.
Use up/down controls to retain actual publication author order. Author detail
links back to its indexed papers/articles, and publications link to their authors.
Add verified title/year/journal or publisher/DOI/web URL manually. Check the link
verification box only after checking it against the publication. Only checked
links get an Open verified publication action; confirming a name does not
implicitly verify its link. No network bibliographic lookup or paid API is used.

## Editions, correction changes and failure handling

Occurrence data is derived from current corrected passages and audio edition,
not saved passage numbers from an earlier transcription. Whole-name phrase
matching uses Unicode word boundaries, ignoring case, repeated whitespace and
common dash variants. A passage matching multiple aliases appears once.

Reference anchors use quoted passage wording in the same episode. If an edition
or correction changes that wording, the old entry remains but may have no current
matches: review its aliases/reference. Existing review decisions are preserved.
Unknown reference titles are not merged merely because adjacent passages mention
a paper; review duplicates and reject redundant suggestions as appropriate.

Indexes refresh on opening the section, app resume, preparation changes, returning
from transcript editing and Refresh. Transcript/correction load failures are shown
explicitly. An unreadable journal does not silently turn into an uncorrected index.
A stale result is rejected before navigation/playback; refresh and try again.

The registry is saved on this device under the app's application-support directory:
`indexes/registry.json`. Atomic writes, file locking and comparison with the saved
revision prevent overwriting concurrent registry edits. Derived word postings and
occurrences live in memory and rebuild from source, so old timing isn't trusted.
No audio/transcript file is altered by indexing. Processing is limited to available
transcripts; untranscribed episodes cannot provide passage occurrences.

## Backup and transfer

Export indexes saves JSON on macOS. On iOS it copies the JSON to the clipboard
because the native save-location operation is unavailable there; paste into a
file to keep a backup. Import indexes selects a JSON file, validates schema,
links and author references, then asks before replacing this device's registry.
The registry contains review decisions/aliases/quoted anchors, not audio or full
transcript editions. The receiving device must have the matching episodes prepared
or bundled; occurrences are derived locally. Export before replacing your registry.

Starter vocabulary: data/index_vocabulary.json, bundled snapshot at
flutter_app/assets/data/index_vocabulary.json. Future vocabulary edits do not
replace existing reviewed entries. The automatic detector is deliberately a
review aid, not a complete taxonomic or bibliographic extraction service.
