# CommonDescentListing Flutter App — Implementation Plan

Status: Phase 5 local YAML import/persistence/reset implemented; manual verification pending. Phase 6 has not started.
Created: 31 October 2026.

## 1. Objective and governing criteria

Build a Dart/Flutter application for browsing Common Descent episodes and their news items using the existing Option 2 YAML dataset. Keep `generate_segments_yaml.py` as the data generator for now.

All generated or modified code must comply with [PROGRAMMING_CRITERIA.md](../PROGRAMMING_CRITERIA.md). This applies to Python, Dart, Flutter, tests, scripts, and configuration-generation code. Read the criteria before each implementation task.

Implement one authorised phase at a time. Stop at its checkpoint, report changes and outstanding verification, and wait for David's confirmation unless he has authorised continuing. Tests, `flutter analyze`, `flutter run`, builds, and Python refresh commands are for David to run unless he explicitly requests otherwise. Do not create commits, push, tag, or change branches without an explicit request.

## 2. Initial scope and assumptions

The first version will:

- Load a bundled copy of the current YAML and work offline.
- Show numbered episodes and unnumbered side episodes.
- Show an episode detail view containing its news and discussion segments.
- Offer a separate searchable news view with links back to its episode.
- Search by episode title, episode number, and news headline; filter by content type.
- Show published timestamps accurately, with clear distinctions between item timestamps and whole-news-section timestamps.
- Allow opening a valid episode source URL in the system browser.
- Permit replacing the local catalogue with another generated YAML file in a later phase.

Use a responsive design for phone and desktop layouts. Proposed initial development target: macOS, with Android and iOS compatibility considered in the shared design. Confirm the actual first release platforms in Phase 0 before platform scaffolding. Web support and distribution are not assumed.

Audio playback, downloading audio, accounts, cloud sync, bookmarks, automatic RSS fetching inside Flutter, editorial headline correction, and app-store publishing are outside the initial scope. None is needed to display the existing data.

The app will not execute Python. Dataset generation stays a separate developer operation.

## 3. Existing data and constraints

The project currently contains:

- `generate_segments_yaml.py`: RSS-to-segment YAML generator.
- `main.py`: Python entry point.
- `data/segments.yaml`: generated Option 2 catalogue.
- `data/segments.rss.xml`: source RSS snapshot.

The last generated snapshot contained 391 feed entries represented by 1,630 segment records, including 1,016 news records. These are reference counts, not permanent acceptance thresholds.

The current YAML has a `podcast` mapping and `segments` list. Relevant segment fields are:

| Field | Interpretation |
| --- | --- |
| `episode_number` | Nullable string; preserve suffixes and fractions such as `18A` and `37.5`. |
| `episode_title` | Episode title; repeated across its segments. |
| `guid` | Episode identity shared by its segment records. |
| `source_url` | Optional external episode page link. |
| `segment_type` | Currently `News`, `Main Discussion`, or `Episode`. |
| `segment_title` | Nullable segment or headline title. |
| `segment_label` | Optional label such as discussion Part 1 or Part 2. |
| `start_time` | Optional segment start; individual inferred news headlines currently have no start time. |
| `news_start_time` | Optional start of the whole news section, not of an individual headline. |
| `news_raw` | Original news summary; retain it for checking inferred splits. |
| `needs_review` | Optional boolean flag for inferred or incomplete news data. |
| `headline_split_method` | Optional provenance for automatically inferred headline boundaries. |

Important limitations:

- Publication dates and audio URLs are not in the current segment YAML. Do not display invented dates, durations, artwork, or playback controls.
- Preserve source order as the initial ordering. Do not label it strictly chronological or numerically sort episode-number strings.
- Group records by `guid`, not title or episode number. Distinct episodes may have similar titles or no number.
- Never deduplicate news records merely because their titles match. The YAML does not yet provide stable per-segment IDs; use episode identity plus source position for session-level identity, not for future durable bookmarks.
- Missing news records mean news is not listed in this dataset; they do not prove the episode had no news section.
- Headline splits are heuristic. Explain this briefly in relevant views and make `news_raw` available; do not present inferred boundaries as manually verified.
- The RSS feed may expose only the publisher's available archive. Do not claim an independently verified complete archive.

## 4. Proposed architecture

Keep the Flutter application in `flutter_app/` so the existing Python code and canonical data remain intact.

```text
CommonDescentListing/
  AGENTS.md
  main.py
  generate_segments_yaml.py
  data/
    segments.yaml
    segments.rss.xml
  docs/
    PROGRAMMING_CRITERIA.md
    plans/FLUTTER_APP_IMPLEMENTATION_PLAN.md
    qa/
  flutter_app/
    assets/data/segments.yaml
    lib/
      main.dart
      app.dart
      models/
      data/
      features/episodes/
      features/news/
      widgets/
    test/
```

Responsibilities:

- Models: immutable podcast, episode, and segment objects; nullable fields represented explicitly.
- Parser: YAML decoding, schema checks, source diagnostics, typed conversion, and timestamp validation.
- Repository: catalogue loading and episode grouping; bundled/local-file sources behind one interface.
- Controller: shared catalogue state, search/filter state, selection, and import state.
- Widgets: rendering and user interaction; no YAML decoding or duplicate search rules in widgets.

Start with Flutter SDK state mechanisms such as a small `ChangeNotifier` controller. Do not add a state-management framework without a demonstrated requirement. Candidate external capabilities are YAML parsing, URL launching, and later file selection/local storage. Choose compatible maintained packages and pin resolved dependencies during their implementation phases; this plan does not prescribe unverified package versions or APIs.

The canonical dataset remains `data/segments.yaml`. Flutter uses a deliberate asset snapshot at `flutter_app/assets/data/segments.yaml` declared in `pubspec.yaml`. Document how David copies a regenerated dataset into that asset; avoid two independently edited datasets. A future sync helper is optional and needs its own scoped task.

## 5. Screen behaviour

### Episode catalogue

Display one entry per grouped episode with title, optional number, and listed-news count. Support search and a filter for numbered versus unnumbered episodes. Use neutral labels such as “Side episode” when no richer series classification exists. Retain source order when clearing filters.

### Episode detail

Display the title, optional episode number, discussion parts and available times, news headlines, and source link. Distinguish “News section starts at …” from an individual item's start time. For missing values, show “Time unavailable” or omit the optional label rather than displaying `null` or zero. Include a readable original-news-summary expansion where available and a concise notice that automatic headline splits may need review.

### News catalogue

Display each news record with its headline and episode context. Search headlines and episode titles/numbers. Selecting a record opens the correct episode and identifies the selected item. Show a sensible fallback for untitled news sections. Preserve duplicate titles in different records.

### General states and accessibility

Provide loading, empty catalogue, no search matches, invalid data, and file-import error states. Use readable text, semantic labels, keyboard access, adequate contrast, and layouts that accommodate enlarged text. Use a narrow-screen navigation flow and a wider list/detail arrangement where appropriate. Expose raw technical diagnostics only in an expandable details area when needed to resolve a data error.

## 6. Data validation and replacement

- Support the current unversioned format explicitly as the legacy v1 contract. Do not change the Python schema as part of the Flutter skeleton.
- Reject an invalid YAML document, missing top-level structures, or incorrect collection types with a useful message.
- Require a non-empty episode `guid` for grouping; report the source record index for an invalid record. Do not silently drop records or invent episode identities.
- Validate required title/type fields, nullable optional fields, boolean review flags, and timestamp syntax/ranges. Keep episode numbers as strings; optionally normalise scalar numeric values from manually supplied files without losing fractional/suffix forms.
- Accept unknown extra fields for forward compatibility. Preserve unknown segment types with a generic display rather than discarding them; reject malformed known fields.
- Validate the whole replacement catalogue before activation. On failure retain the current valid catalogue and explain the error.
- Do not render HTML from imported fields or execute imported content. Treat URLs as data and allow only valid `http`/`https` source links.
- Apply a documented file-size limit before parsing imported files, chosen from the actual dataset size with reasonable growth allowance during the import phase.
- For persistent imports, save the validated candidate before switching the active catalogue. On restart, use the last valid imported catalogue; fall back to the bundled snapshot if local data is unavailable or invalid, with a clear notice. Provide an explicit reset-to-bundled action.

## 7. Phased implementation

### Phase 0 — Agree platform and data contract

**Goal:** settle the minimum decisions needed to start implementation.

**Scope/tasks:** confirm initial target platforms; record the field contract above; inspect representative main, news, and side-episode records; agree navigation and source-order behaviour; record the asset-update workflow.

**Acceptance criteria:** a documented contract covers nullable fields, grouping, timestamps, heuristic news, unsupported records, and catalogue replacement. No platform-dependent assumption remains unresolved before scaffolding.

**Done when/evidence:** David reviews the contract and initial platform choice. Record decisions in this plan or a linked decision document. Stop before Phase 1.

### Phase 1 — Flutter project and offline shell

**Goal:** establish the app without changing the Python generator.

**Scope/tasks:** create `flutter_app/` for the approved platforms; add theme/navigation shell, asset declaration and bundled snapshot; document setup and data-copy instructions. Keep code split by responsibility.

**Acceptance criteria:** the project can be opened in the chosen IDE; the app shell has loading/error placeholders and the asset path resolves during David's local launch. Python files remain usable.

**Done when/evidence:** files and setup instructions are delivered; David runs dependency resolution, analysis, and a launch on the selected target, then reports results.

### Phase 2 — Typed models, parser, and repository

**Goal:** load the actual catalogue reliably.

**Scope/tasks:** implement models, validation, grouping by GUID, ordered segments, timestamp conversion, and one repository API. Add focused parser/repository tests for genuine data risks.

**Acceptance criteria:** every valid source segment is represented once; all distinct episode GUIDs are retained; missing optional values work; invalid data produces useful diagnostics; unknown fields/types follow the stated contract. News and discussion timestamps remain distinct.

**Done when/evidence:** David runs the focused tests. Compare grouped episode and segment counts to the input fixture, not fixed global counts; verify representative fractional/letter-suffixed and unnumbered episodes.

### Phase 3 — Episode catalogue and detail

**Goal:** browse episodes and inspect their segments offline.

**Scope/tasks:** implement the episode list, search, numbered/side filter, detail view, original news summaries, available-time labels, source links, responsive navigation, and empty/error states.

**Acceptance criteria:** selecting any list entry opens its correct grouped episode; multiple discussion parts remain separate; unknown times are not zero; valid source links open externally; invalid URLs do not produce a broken action; small and wide layouts remain usable.

**Done when/evidence:** focused widget coverage protects grouping/selection and time labels. David records manual narrow/wide layout, keyboard, enlarged-text, and offline checks with results.

### Phase 4 — News browsing and shared search

**Goal:** find news topics independently of episode browsing.

**Scope/tasks:** implement the news list, shared search logic, navigation to the relevant episode/item, original-summary access, and concise review notices.

**Acceptance criteria:** search is case-insensitive and trims whitespace; clearing search restores source order; duplicate headlines are preserved; selecting a headline reaches its correct episode; a news-section timestamp is never labelled as the specific headline's time.

**Done when/evidence:** David runs focused search/navigation tests and manually reviews known examples such as episode 255. No additional news content is inferred beyond the existing YAML.

### Phase 5 — Local YAML replacement and persistence

**Goal:** update the catalogue without rebuilding the app.

**Scope/tasks:** add platform-appropriate YAML selection, bounded validation, safe activation/persistence, catalogue-origin/status display, import errors, and reset-to-bundled behaviour. Keep both data sources behind the same repository interface.

**Acceptance criteria:** a valid generated file replaces the displayed catalogue; cancellation changes nothing; malformed or oversized files preserve the current valid data; restart restores the selected catalogue; reset returns to the bundled data; incomplete writes never become active.

**Done when/evidence:** David exercises valid import, cancelled import, invalid input, restart, and reset on each selected platform. Record results and any platform restrictions.

### Phase 6 — Acceptance review and handover

**Goal:** establish whether the initial app meets its requirements.

**Scope/tasks:** review the approved requirements, accessibility, offline behaviour, startup with the actual catalogue, search responsiveness, import recovery, and documentation. Fix only issues found within this scope.

**Acceptance criteria:** agreed platform checks pass; every critical defect is resolved or explicitly tracked; app counts match the loaded dataset; no claim implies automatically reviewed headlines or a proven complete archive; operating and update instructions are clear.

**Done when/evidence:** store a pass/fail checklist under `docs/qa/` with environment, tester, date, steps and notes/screenshots. Record implementation status separately from David's verification status. Publishing is a separate future task.

## 8. Verification commands for David

These are proposed handover commands, not commands executed while preparing this plan. Run only the commands appropriate to the current phase, from `flutter_app/` once it exists:

```zsh
flutter pub get
flutter analyze
flutter test test/<affected_test_file>.dart
flutter run -d <approved-device-id>
```

Run a wider suite or release build only at the relevant acceptance/release checkpoint. Select device IDs and platform build commands after the platform decision; do not assume a device or signing setup.

Manual checklist:

- Load the bundled data with networking unavailable.
- Inspect numbered, fractional/suffixed, and side episodes.
- Check episode 255's news summary and separate discussion-part times against the YAML.
- Search news and episode titles; inspect empty results and duplicated headlines.
- Confirm unknown values and review notices are clear.
- Open an episode source link and return to the app.
- Check narrow/wide layouts, keyboard navigation, and enlarged text.
- When Phase 5 exists, test import/cancel/failure/restart/reset without losing a valid catalogue.

## 9. Risks and decisions to track

| Risk/decision | Planned handling |
| --- | --- |
| Initial release platforms unspecified | Confirm in Phase 0; macOS is a proposal, not an approved release requirement. |
| Inferred news boundaries can be incorrect | Preserve raw summary, mark review status, and avoid claiming editorial verification. |
| No dates in segment YAML | Use source order; defer date sorting until the schema explicitly supplies dates. |
| No stable segment IDs | Use source-position identities for current navigation; defer durable item references. |
| YAML corruption or incompatible import | Validate before activation; retain previous valid data and bundled fallback. |
| Parse time and memory growth | Measure with actual data during authorised verification; add background parsing only if justified. |
| Asset copy becomes stale | Document the explicit copy/update step and show dataset origin; avoid hand edits. |
| Existing catalogue represents feed availability | Describe it as the loaded catalogue, not an independently verified complete archive. |

## 10. Completion reporting and current status

For each implemented phase, report the work, files created/modified/removed, tests created/changed, checks actually run, David's commands/manual checklist, remaining risks, phase status, and suggested commit message. If no checks were run, say `None — manual verification requested.`

Current status: Phase 1 scaffolding and shell are implemented in `flutter_app/`, using macOS as the provisional initial target in response to David's instruction to implement Phase 1. Platform confirmation from Phase 0 remains outstanding; Android/iOS runners have not been generated. Phase 0 is not marked independently approved or complete.

Phase 5 adds native YAML selection, a 5 MiB bounded read/validation path, save-before-activation persistence, startup fallback, origin/status display, and reset to bundled data. Existing parser/repository and episode/news views remain in use. File-picker/storage dependencies and macOS read-only user-selected-file entitlements were added. Focused tests were created but not run. No dependencies were resolved, tests or analysis run, builds made, or app launched by the assistant. See `../qa/PHASE_5_MANUAL_VERIFICATION.md` for the current checkpoint. Do not begin Phase 6 until authorised.

Suggested commit message for this planning task: `Document Flutter catalogue app plan and programming criteria enforcement`.
