# Repository workflow

## Development location

All development and image builds use VM-laptop. Follow the canonical VM/build,
checkout and deployment procedure in `/home/dev/projects/AGENTS.md`; older VPS
build commands and former laptop/VPS workspace paths in this repository are
superseded. The VPS only receives prepared artifacts for requested deployments.
Apple builds retain the existing macOS runner exception under that procedure.

## Repository workflow

Canonical repository: `agawlbb/coffey-table-recipes`; default branch: `main`.
Follow the VM-wide working procedure in `/home/dev/projects/AGENTS.md`.
Use the existing checkout on `main`, one task at a time; no routine task
branches, extra worktrees or ownership claims. Commit and push completed source changes to `main`.
Use only relevant checks; do not repeat passing checks without a concrete reason.
Questions and status checks are read-only. Preserve unrelated work and credentials.
Deploy only when the user explicitly requests deployment. In every answer state
whether deployment and an app build are needed; do not automatically do either.

## Project boundaries

- This integration belongs to the combined repository. Its runtime source is in root `custom_components/`; support files and tests are in `home-assistant/`.
- Keep credentials, tokens, private Firebase settings, Home Assistant account backups and personal data out of Git. Do not create another remote repository or rewrite published history without explicit authorization.
- Follow the user's requested scope. Instruction changes do not authorize functionality/dependency changes, builds, installation, deployment, releases, or repository/security settings changes. Do not automatically update a running Home Assistant installation; deploy only when explicitly requested.

## Keep the project simple

Avoid overengineering. Treat these as small personal projects unless the user says
otherwise. Use the simplest maintainable implementation that meets the current
requirements. Brief deployment downtime (including a couple of minutes) is
acceptable. Prefer copying files and restarting a process over release frameworks,
zero-downtime machinery, repeated setup migrations, compatibility modes, feature
flags or abstractions for hypothetical future scale. Keep setup separate from
routine deployment. Preserve authentication, credential privacy and protection
against real data loss, and use proportionate tests. Explain a concrete need before
adding complexity; do not introduce unrequested features or operational workflows.
