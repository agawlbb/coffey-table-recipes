# Repository workflow

## Repository workflow

Canonical repository: `agawlbb/home-assistant-coffey-table-recipes`; default branch: `main`.
Follow the VM-wide working procedure in `/home/dev/projects/AGENTS.md`.
Use the existing checkout on `main`, one task at a time; no routine task
branches, extra worktrees or ownership claims. Complete the requested outcome,
including deployment when applicable, then commit and push to `main`.
Use only relevant checks; do not repeat passing checks without a concrete reason.
Questions and status checks are read-only. Preserve unrelated work and credentials.

## Project boundaries

- This standalone Home Assistant integration, the Flutter client and PHP server remain separate repositories. Existing laptop integration checkout: `C:\Users\mailb\StudioProjects\home-assistant-coffey-table-recipes`.
- Keep credentials, tokens, private Firebase settings, Home Assistant account backups and personal data out of Git. Do not create another remote repository or rewrite published history without explicit authorization.
- Follow the user's requested scope. Instruction changes do not authorize functionality/dependency changes, builds, installation, deployment, releases, or repository/security settings changes. A requested fix to the running integration includes deployment and verification through its documented access.

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
