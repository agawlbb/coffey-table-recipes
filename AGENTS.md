# Working rules

## Keep it simple

This is a small personal project. Use the simplest maintainable implementation.
A couple of minutes of deployment downtime is acceptable. Prefer copying files
and restarting one process. Keep setup separate from routine deployment. Do not
add release frameworks, zero-downtime machinery, compatibility layers, feature
flags or abstractions for hypothetical scale. Preserve authentication, credential
privacy and protection against real data loss. Explain a concrete need before
adding complexity. Stay within the requested behavior; no unsolicited features.

## Repository workflow

Canonical repository: `agawlbb/coffey-table-recipes-vps`; default branch: `main`.
Follow the VM-wide working procedure in `/home/dev/projects/AGENTS.md`.
Use the existing checkout on `main`, one task at a time; no routine task
branches, extra worktrees or ownership claims. Complete the requested outcome,
including deployment when applicable, then commit and push to `main`.
Use only relevant checks; do not repeat passing checks without a concrete reason.
Questions and status checks are read-only. Preserve unrelated work and credentials.

This is the VPS backend only. InMotion remains a separate server repository.
Do not create repositories, rewrite published history or change protections
unless explicitly requested.

## Development, data and deployment

- Use the existing shared development container through
  `/home/debian/.local/bin/dev exec`. Respect workspace instructions.
- Keep credentials, private config, dependencies, logs and generated files out
  of Git. Dependencies are project-local and locked. Never print secrets.
- The persistent MariaDB database runs on the VPS private database network. Never use production data
  or production containers for development tests. Use disposable SQLite fixtures.
- The owner's requirements define correctness; existing tests are evidence, not
  additional requirements. Test failures never authorize adding unrequested
  restrictions, version comparisons, conflict handling or other behavior.
- Before editing, state the observable behavior and smallest relevant checks.
  Use affected PHP fixtures or wire checks for the behavior changed, deployment
  tooling tests only when that tooling changes, and diff review for documentation.
  A full suite requires an explicit request for that suite; a deployment, release,
  shared-code change, merge or push does not authorize it. Explain a concrete
  reason before broadening focused checks. Do not repeat passing checks without
  a relevant new change, failure or unresolved concern.
- Classify a failing test before changing code: fix requested behavior; remove or
  correct tests imposing unwanted behavior; ask about unclear product decisions.
  Test observable outcomes rather than internal counters, queue layouts or retry
  counts. Preserve useful authentication, account isolation and actual user-data
  protection coverage. Do not retain obsolete tests as a competing specification.
- Separate test execution from build/deployment/delivery. Keep live health,
  deployed-source and package verification, but no automatic test-suite hooks.
  Report exactly what was checked and its limits; passing tests do not establish
  untested requirements. A test cleanup does not authorize production changes.
- Keep private/state directories outside replaced code. Routine deployment copies
  source and restarts the existing process. No cPanel credential belongs here.
- Schema changes and credential imports are explicit setup/maintenance actions,
  never recurring deployment steps. Preserve SQL transactions and replay receipts.
- This repository does not build or publish the app or install the HA integration.

- Child mode for shopping is enforced by hiding app editing controls. Do not add
  server-side child-mode restrictions or an inMotion HTTP policy dependency.

## VPS CPU policy

Production uses `cpu_shares: 1024`; shared development uses `cpu_shares: 128`.
Do not set `cpus`, `cpu_quota` or `deploy.resources.limits.cpus` hard caps.
Preserve existing memory, swap, process, security and restart settings. Deployment
must retain the policy in its installed Compose configuration and verify
`CpuShares=1024` and effective `/sys/fs/cgroup/cpu.max` beginning with `max`.
The VPS reference is `agawlbb/vps_admin`, branch `work`, commit `9463376`.

## Current VPS deployment

Use [DEPLOYMENT.md](DEPLOYMENT.md) for standard container preparation, rsync and restricted
SSH deployment. Older host-administrator deployment scripts are not the routine
path. Infrastructure and migration changes require separate authorization.
