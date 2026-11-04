# Crossref publication lookup — first integration

4 November 2026. Use the retained small indexer. Remove the rejected large model's
exclusive cache; preserve the small cache and historical comparison results.

## Goal and scope

Resolve sufficiently specific publication clues through Crossref's free metadata
API. First implement an optional ZSH lookup tool and bounded Marsupials trial,
separate from offline indexing and published app data. No ChatGPT request, model
training or automatic publication/author confirmation.

## Acceptance

- An explicit query plan selects publication entries or unidentified mention
  groups, retaining episode, edition, literal evidence and index/baseline hashes.
- Search by topic/title, author, journal and known publication cutoff, or resolve
  a supplied DOI. Analyst-supplied queries remain distinct from transcript text.
- Cache raw responses, timestamp retrieval, respect serial request spacing and
  server limits; support offline replay, limited requests and explicit errors.
- Retain title, authors, publication dates, journal/publisher, DOI, Crossref type
  and source URL. Crossref relevance score is not a confidence probability.
- Show candidate metadata beside original evidence in a review report. DOI
  resolution confirms a metadata record, not the identity of a spoken reference.
- No input index modifications, listener decision changes or source promotions.
- Record results/limits and reuse the cache on repeat runs. A generic mention
  without enough clues remains unidentified; news articles may not be in Crossref.

## Later integration

After review, add an app action for unresolved publication mentions. Present the
candidate title/author/date with transcript context; accepting a particular match
can then attach source-backed bibliography to that occurrence and link its
publication authors. Keep Papers versus Articles subject to review: Crossref's
journal-article type does not establish that the speaker referred to the research
paper rather than a news report about it. Do not add every coauthor to the spoken
Authors index unless actually mentioned. Cache service belongs on the preparation
server; listener browsing can remain offline. API errors must not fail transcription.

Sources: https://www.crossref.org/documentation/retrieve-metadata/rest-api/ and
https://github.com/CrossRef/rest-api-doc . No API key is required; optional contact
email can use the polite pool. Do not infer a contact address.

## Implementation status

Optional ZSH lookup and separate review output implemented. Marsupials trial:
initial six bounded Crossref queries covering four reference groups; plausible
matches for three. A corrected author/DOI lookup and advisory date search then
identified the sea-scorpion paper (nine unique lookups overall). No published changes or payment.
Three offline fixtures passed; live trial and zero-request cache replay completed.
See outputs/crossref-trial/marsupials/README.md. App review/apply integration and
independent match confirmation are not part of this first step.

## Date-filter correction

David supplied JC Lamsdell and the complete paper citation. DOI lookup confirmed
10.1016/j.cub.2020.08.034. Crossref’s November 2020 issue date had excluded it from
searches cut off at the September episode date. Dates are now advisory by default;
explicit `strict_publication_cutoff: true` can request the older strict behaviour.
Candidate dates later than the episode receive a review warning. The corrected
search now returns the paper first; input evidence and published app data remain
unchanged. Updated offline fixtures passed.

## Approved citation application

David explicitly authorised updating the index with the Lamsdell paper and supplied
full title, authors, journal volume/issue, pages, issue date and Open Archive status.
Apply only this citation: correct the named author, consolidate duplicate paper
headings, remove unrelated paper assignments for its Marsupials discussion, retain
literal transcript anchors and all coauthors in bibliography (without inventing
spoken coauthor mentions). Back up source sidecar, summary, bundled local index
and app registry. Use the registry lock and compare source bytes before writing.
Refresh the portable library export and record hashes/affected IDs. No transcript,
audio, credentials or Git changes; no additional paid lookup required.
