# Programming Criteria — CD List

Consolidated on 31 October 2026 from `/Users/david/PycharmProjects/Sudoku_01/docs`.

## Scope and interpretation

Use these criteria when programming CD List. The primary source is `CURRENT_STATE.md`, which explicitly defines the AI assistant's operating instructions. Supporting documents supply acceptance, design, and verification practices.

The workflow rules below are transferred from that source. Python examples and applications to the RSS/YAML exporter are adaptations for this project, not verbatim Sudoku requirements. Sudoku gameplay, premium access, app-store distribution, mobile UI, and theme-pack requirements are not requirements for this project.

## 1. Keep work focused

- Use zsh for shell scripts and terminal command examples (David's project preference). Use `#!/bin/zsh` for shell scripts and `zsh` for Markdown shell blocks. Dart/Flutter app code and the retained Python data generator keep their implementation languages.

- Implement one clearly defined task or numbered phase at a time.
- Preserve the existing architecture and avoid unrelated refactoring.
- Inspect only files relevant to the task and dependencies that require inspection.
- Read this document first, then the applicable implementation plan and affected source files.
- Do not repeatedly rescan files already examined or explore the whole repository without a concrete need.
- Prioritise implementation quality over repeated verification and unnecessary AI credit consumption.

Source: `CURRENT_STATE.md` — Credit-Conscious Workflow, File Inspection, Project Principle.

## 2. Define acceptance before calling work complete

For a planned issue or implementation phase, record:

1. Goal.
2. Scope.
3. Tasks.
4. Acceptance criteria.
5. Done-when conditions and required evidence.

Keep implementation status distinct from verification status. Do not mark a task fully verified merely because the code is written; identify missing checks or evidence. For manual checks, record the environment, date, tester, steps, pass/fail results, and relevant notes or screenshots.

Sources: `GITHUB_SPRINTS.md` — issue template, completion-evidence requirements, Issue 5 closure status; `testing_types.md` — Manual QA And Release Checklists.

## 3. Maintain clear ownership and reusable logic

- Keep common rules and configuration in one authoritative location rather than duplicating them at call sites.
- Keep business rules out of presentation code and use the existing service or abstraction boundaries where applicable.
- Prefer incremental changes over a large rewrite.
- Keep existing behaviour stable outside the requested change.
- Respect existing file-size guardrails if the project defines them. The reviewed docs do not provide a transferable numeric line limit; do not invent one.

Application to CD List: keep the RSS URL and shared parsing/serialization helpers defined once; let `main.py` delegate to the exporter. Introduce additional modules only when the task requires them.

Sources: `FREE_FULL_PHASED_IMPLEMENTATION_PLAN.md` — Phase 0 single source of truth and policy services; `GITHUB_SPRINTS.md` — Issues 5, 6, and 13; `localisation/internationalisation.md` — incremental strategy and stable behaviour.

## 4. Verification is manual by default

Unless David explicitly instructs otherwise, the AI assistant must not run tests, integration suites, application launches, platform builds, or long-running verification commands. The source also specifically prohibits automatic Flutter analysis, Flutter tests/runs, and Shorebird commands.

Instead:

- Recommend the relevant verification commands for David to run.
- Prefer the affected test or smallest relevant check over a full suite.
- State clearly which checks were not run.
- Do not claim tests, builds, or commits occurred unless they actually did.

Python adaptation: do not automatically run `main.py`, test suites, or network-refresh verification as part of a code change. Recommend appropriate commands instead. For this exporter, David can use a saved feed to avoid a network request:

```zsh
.venv/bin/python main.py --input data/segments.rss.xml --output data/segments-review.yaml
```

For an explicitly requested live refresh:

```zsh
.venv/bin/python main.py
```

The live command fetches the RSS feed and overwrites the default segment YAML and RSS snapshot. The review command writes separate review files. Run commands from the project root.

Source: `CURRENT_STATE.md` — Testing Policy, Manual Verification Reminder. The Python commands and their application are project-specific adaptations.

## 5. Choose verification to match the risk

- Use unit tests for isolated parsing, transformation, serialization, and decision logic.
- Use integration checks for the full feed-to-output flow.
- Use manual review for output quality and ambiguity that automated checks cannot establish.
- Use UI, visual, device, and build checks only if the project later gains those components.
- Reserve slower checks for changes whose risk warrants them.

CD List examples: verify missing-field handling, HTML paragraph boundaries, fractional episode numbers, YAML validity, and preservation of source records when those areas change. Review heuristic headline splits rather than assuming they are verified facts.

Source: `testing_types.md` — test-layer purposes and How The Layers Fit Together. The exporter examples are adaptations, not additional Sudoku rules.

## 6. Handle reported errors narrowly

When David supplies compiler, analyzer, runtime, or test output:

- Inspect the relevant files.
- Fix the reported issues without unrelated changes.
- Ask David to rerun the affected command.

Source: `CURRENT_STATE.md` — Handling Errors; runtime errors are the Python adaptation.

## 7. Respect phase checkpoints

For numbered implementation work:

1. Implement the authorised phase only.
2. Stop at the phase boundary.
3. Summarise the completed work and remaining issues.
4. List manual verification steps for David.
5. Wait for confirmation before starting the next phase unless David already instructed otherwise.

Source: `CURRENT_STATE.md` — Phase Workflow, Manual Verification Reminder.

## 8. Git actions require an explicit request

Do not create or amend commits, push, create tags, or change branches unless David explicitly requests it. Remind David to review and commit manually if appropriate, and provide a suggested commit message. Do not imply that a commit has been made.

Source: `CURRENT_STATE.md` — Git Policy.

## 9. Report completion accurately

At the end of an implementation task, report:

1. Work completed.
2. Files created.
3. Files modified or removed.
4. Tests created or modified.
5. Tests actually run by the assistant; normally, `None — manual verification requested.`
6. Commands David should run.
7. Manual verification checklist.
8. Outstanding issues or risks.
9. Current phase status, or `Not applicable` for unphased work.
10. Suggested Git commit message.

Do not confuse implementation complete with verification complete.

Source: `CURRENT_STATE.md` — Completion Report. Removed files and unphased status are clarifying adaptations.

## Source documents

All source paths below are relative to `/Users/david/PycharmProjects/Sudoku_01/docs`:

- `CURRENT_STATE.md`: primary programming and assistant workflow criteria.
- `testing_types.md`: selection and purpose of verification layers.
- `GITHUB_SPRINTS.md`: issue structure, acceptance criteria, completion evidence, shared policy/configuration, and existing file-size guardrails.
- `FREE_FULL_PHASED_IMPLEMENTATION_PLAN.md`: incremental phases and central ownership of rules.
- `localisation/internationalisation.md`: incremental changes and stable behaviour.

Other documents in the directory mainly describe Sudoku features, release procedures, marketing/localisation content, or operational records. Their product-specific requirements have not been transferred to CD List.
