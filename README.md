# CommonDescentListing

## Flutter application

The macOS app in `flutter_app/` includes episode/news browsing, shared search, segment details, and Phase 5 local YAML import with persistence and reset to bundled data. See [Flutter setup](flutter_app/README.md) and the [Phase 5 checklist](docs/qa/PHASE_5_MANUAL_VERIFICATION.md). Acceptance review remains Phase 6.

All code changes must follow [programming criteria](docs/PROGRAMMING_CRITERIA.md).

## Python data generator

Run `main.py` in PyCharm to fetch the Common Descent RSS feed and export Option 2 YAML: one record per news item or discussion segment. All feed items are included, including unnumbered side episodes.

Output files:
- `data/segments.yaml`: segment records.
- `data/segments.rss.xml`: original RSS snapshot.

No third-party packages are required. Missing fields remain null. Numbered episode IDs come from episode titles. News headlines are split heuristically on commas/semicolons and marked `needs_review: true`; every record preserves the original `news_raw` summary. Individual news item `start_time` values remain null. `news_start_time` is the timestamp for the whole news section. Published main discussion parts get separate records with their explicit timestamps. Other sections such as announcements and patron questions are not extracted.

Command-line usage:
```zsh
python main.py
python main.py --output data/custom.yaml
python main.py --input data/segments.rss.xml --output data/offline.yaml
```
