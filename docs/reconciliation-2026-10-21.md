# Laptop and GitHub reconciliation — 2026-10-21

Both working trees were clean at inspection. Flutter main had diverged: local
commit `c6b466d` contained startup/shopping rate-limit recovery, while origin/main
contained four deployment trust-store/security preparation commits through
`b61f228`. Merge `dd8419b` preserves both histories without conflicts or rewriting
commits. Backend main already matched origin/main at `6934f45`.

The live web version endpoint was read on October 21 and still reports
1.8.3/build 27, source `94b102427650021ce0bc899ad8fd79deef877c6d`.
The Android delivery folder contains `CoffeyTableRecipes-1.8.3-build27.apk`.
The last verified iOS TestFlight delivery is also 1.8.3/build 27; see releases.md.
Thus the last delivered release is three calendar days old and lacks one app
behavior fix (rate-limit recovery) plus the deployment-client security changes.

Existing tag v1.8.4 points to `db618d4`, excludes the local rate-limit fix, and
has validation-only evidence, not an app build or production deployment. Keep
that tag immutable. Recommend a new 1.8.5/build 29 release from reconciled main
to deliver the recovery fix and use the patched deployment client. The trust-store
change itself affects publishing tooling, not the installed native application's
runtime. No build, release, hosted deployment or tag change was requested or
performed during reconciliation.

Validation: Flutter analysis and all 358 Flutter tests passed; the four offline deployment-client tests
passed using the pinned Requests 2.32.5 and certifi 2026.10.19 in an ignored local
environment; pip check and git diff --check passed. Test deployment messages
come from mocks and do not indicate a real upload.

## Repository history correction

The owner subsequently authorized removing an unrelated side-history imported
by consolidation. A verified local recovery bundle preserves the former main
head `d92194db2509bf83b0928750b4abc6d9822600c2` and all existing release tags.
Main was restored to this reconciliation's `bba2cf2` before this documentation
cleanup. This excludes all 34 side-only commits and the two consolidation
commits from main while retaining every recipe commit. Six unrelated files
were removed, along with obsolete unrelated-project references in release
documentation. Recipe application code, tests, platform sources, dependencies,
deployment security tooling and release tags are unchanged.

The working-copy inventory found one active checkout and three existing CTR
recovery snapshots in the Repository Archive. Those clean archival snapshots
remain recovery material, not active copies; they were not reset or purged.
The separate archived repository and the backend were not modified.

Validation: recipe source and deployment tooling match the previously verified
reconciliation exactly (358 passing Flutter tests and clean analysis). The four
offline deployment-client tests and dependency consistency check passed again.
No app build, workflow dispatch, hosted deployment or secret copying occurred.
