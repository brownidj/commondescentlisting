# Consolidate legacy episode outputs

Authorised 4 November 2026. Move outputs/episode-054-wallace to
outputs/episodes/6db090f54c04b34e2f1abdfefcb67c97/legacy and
outputs/episode-072-plesiosaurs to
outputs/episodes/d111dc1276ec736e782a70ac43fed94c/legacy.

Preserve every original file and existing runs. Update documentation links and
legacy zsh project-root derivations for the deeper location. Preserve original
script bytes in each legacy folder's relocation/original-scripts. Leave recorded
paths in raw logs, manifests, transcript JSON and run snapshots unchanged because
they are historical provenance/checksummed evidence; document old-to-new mapping.
No symlink aliases or re-created old top-level folders. Do not change app packages,
working files, listener transcripts, active editions or preparation jobs.

Done when original file hashes are accounted for at the new locations (modified
scripts have byte-identical backups), destination scripts retain executable mode,
documentation points to the new location, and the relocation report is saved under
outputs/episodes. No transcription, tests, builds, app launches or Git mutations.

Completed: 44 Wallace and 43 Plesiosaurs original files accounted for by SHA-256
and mode. Modified scripts/readmes retain original-byte backups. Documentation
links updated; historical evidence paths preserved. See outputs/episodes/RELOCATION.md
and relocation-inventory.json. No tests, processing, launches or Git mutations.
