# Repository consolidation — 2026-11-20

Canonical repository and checkout: `agawlbb/coffey-table-recipes`, `/home/dev/projects/coffey-table-recipes`, branch `main`.

The mobile source stays at root to preserve the existing manually dispatched Android/iOS workflows. VPS source is in `backend/`. Home Assistant runtime source and HACS metadata are at root for HACS discovery; its documentation, tests and test environment are in `home-assistant/`.

The complete main histories of `agawlbb/coffey-table-recipes-vps` (`ab91ea2`) and `agawlbb/home-assistant-coffey-table-recipes` (`47722c8`) were joined with merge commits without rewriting published history. The original GitHub repositories are archived as historical records, retaining their releases, tags and issues. They are no longer development locations.

Rollback archive: `/mnt/share/fileBeans/Retired projects/ctr-before-consolidation-2026-11-20.tar.gz`, with adjacent SHA-256 file. It contains all three pre-consolidation checkouts including `.git` and local configuration, excluding regenerable dependencies/build caches (`vendor`, `.venv`, `.dart_tool`, `build`, `__pycache__`). Keep this archive private. To roll back, verify its checksum and extract into an empty recovery location; do not overwrite active work. Repository archival is reversible in GitHub settings.

Run backend commands from `backend/`. Run integration checks from repository root with `home-assistant/.venv/bin/python`; use `-c home-assistant/pytest.ini` for pytest and `-s home-assistant/tests` for unittest discovery. Integration CI remains manually dispatched and uses these paths. Builds and deployments remain explicit operations; no production source, database or installed integration changes are part of consolidation.

## Focused verification

- Verified every original tracked file maps into the combined tree; backend/runtime integration source is byte-identical except integration repository links. Only layout, instructions, metadata, test import paths and workflow paths changed.
- Verified both original main tips are ancestors of the combined main history.
- Passed 42 integration checks: `test_api.py` (11), `test_keep_engine.py` (20), `test_keep_adapter.py` (11), using the relocated integration virtual environment and unittest discovery from root.
- `git diff --check` passed. Existing mobile workflows remain manual; integration validation was moved to root workflows with corrected paths and explicit manual dispatch.
- Rollback archive gzip integrity, SHA-256 and all three original main refs verified.
- Additional pytest collection was unavailable because the existing local integration environment does not contain pytest. No dependency installation, full suite, app build, workflow dispatch, deployment or production mutation was performed.
