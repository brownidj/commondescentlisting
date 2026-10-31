# CommonDescentListing

## Flutter application

The macOS app in `flutter_app/` includes episode browsing, filters, segment details, and the Phase 4 news catalogue with shared search and exact episode/item navigation. See [Flutter setup](flutter_app/README.md) and the [Phase 4 checklist](docs/qa/PHASE_4_MANUAL_VERIFICATION.md). YAML import/persistence remains Phase 5.

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
