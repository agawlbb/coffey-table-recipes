# Laptop and GitHub reconciliation — 2026-10-21

Both working trees were clean at inspection. Flutter main had diverged: local
commit `c6b466d` contained startup/shopping rate-limit recovery, while origin/main
contained four deployment trust-store/security preparation commits through
`b61f228`. Merge `dd8419b` preserves both histories without conflicts or rewriting
commits. Backend main already matched origin/main at `6934f45`. The unrelated
remote Fan Control Watch branch remains unchanged.

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
