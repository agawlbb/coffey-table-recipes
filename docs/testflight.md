# Signed iOS builds and TestFlight

Current status (2026-10-13): Apple app/extension/App Group registration is complete.
The current team API key was verified as Admin and its private PEM downloaded and
verified through Chrome. After owner GitHub account verification, the current key
ID update succeeded and `ASC_PRIVATE_KEY` was saved. All five required secret
names were verified in repository settings, with existing hosting secrets retained.
The signing workflow is committed locally. Source push, first macOS signing/upload
run, TestFlight processing and physical-device acceptance remain pending. Each
macOS run requires separate explicit user approval. No private key is in Git.

First authorized upload run (2026-10-13): with explicit owner approval, pushed
through `a0fe44d` and dispatched exactly one workflow from `main`, build number
`13`, upload enabled. [Run 38466229058](https://github.com/agawlbb/coffey-table-recipes/actions/runs/38466229058)
passed the Linux preflight. At the last check, `signed-ios` was in progress with
no executed steps and reported waiting for the assigned hosted runner to come
online. No signed package, successful upload or TestFlight availability has yet
been verified. No rerun was triggered; any rerun requires a new explicit approval.

After approximately 16 minutes with no Mac steps executed, the owner explicitly
approved cancellation and one retry. GitHub accepted normal cancellation; the
job later confirmed `cancelled`. A force-cancel request returned HTTP 409, followed
by confirmation that cancellation had already completed. Re-ran only the
`signed-ios` job once using GitHub's job rerun endpoint; GitHub returned success.
The retry keeps source `a0fe44d`, build 13 and upload enabled. Its final signing
and upload outcome remains pending; no additional retry is authorized.

Runner investigation on 2026-10-13: compared GitHub API job metadata and prior
successful logs. Run 38332017587 requested the same `xcode-27` label, began nine
seconds after submission, and completed 16 steps in 8m49s. Its runner image was
`xcode-27-arm64` version `20261006.0244.1`, macOS 27.0.1, region westus/MacCloud.
The current retry was assigned `GitHub Actions 1000000115` but still had zero
steps; the first attempt had been assigned a different runner, 1000000114.
Linux preflight succeeded. This locates the stall before job setup, checkout,
Flutter, Xcode, or Apple authentication. It is consistent with a GitHub hosted
runner startup/connection problem; the exact infrastructure cause is not exposed
by the available API/UI. GitHub's unresolved-incidents API reported no active
incidents at the check. These observations do not establish a billing cause or
prove which image version the current runner would have used. No run was started
or canceled during this read-only investigation.

Correction after detailed-log retrieval on 2026-10-13: GitHub's step/status API
and UI proved inconsistent with its detailed logs. Attempt 2 logs show runner
setup at 17:12 EDT, Flutter tests followed by five iOS configuration tests at
17:15, unsigned Runner.app compilation completed at 17:21, and native archive
compilation through 17:24. These timestamps precede the owner's later account
budget adjustment, so the budget change cannot be credited with starting the
retry. Earlier observations of zero steps described the returned status, not
proof that no code executed. The detailed logs supersede that inference. At this
check there is no verified archive/export/upload success, while GitHub still
reports the job in progress. Do not infer completion or a billing root cause
from the delayed status alone. No additional build was started.

At the subsequent check, Apple API authentication succeeded and the app's builds
endpoint returned no uploads. GitHub then reflected passed Flutter/iOS tests and
an in-progress archive step, but detailed logs still stopped at 17:24 EDT and the
job remained in progress beyond its configured 45-minute limit. Prepared local
archive diagnostics: named stage notices, a 60-second machine-activity heartbeat
that excludes process arguments, and a 25-minute archive/upload step limit. Bash
syntax, workflow YAML and all five iOS configuration tests passed. These changes
are not deployed or executed yet; a new Mac run requires explicit approval.

With explicit owner approval, pushed diagnostics through `214f2aa` and requested
force cancellation of the stale run (GitHub HTTP 202). Dispatched exactly one new
diagnostic run from `main`, build 13, upload enabled (GitHub HTTP 204):
[run 38474737732](https://github.com/agawlbb/coffey-table-recipes/actions/runs/38474737732).
GitHub verified its source SHA matches `214f2aa`. At creation it was pending behind
the old run's unfinished cancellation; the signing concurrency group prevents
overlap. Do not report cancellation or the new build as completed until verified.

Build-only coordination: the current requested scope excludes TestFlight/App
Store upload. Fresh API checks still showed old run 38466229058 in progress and
diagnostic 38474737732 pending, both originally upload-enabled. Requested force
cancellation for both (HTTP 202), without claiming either had completed. The
next authorized run must use `upload=false`. Native archive concurrency now
defaults to two Xcode jobs, configurable with a validated `IOS_XCODE_JOBS`, to
reduce memory pressure on the standard 7 GB runner. This is a diagnostic
mitigation, not a proven fix for the underlying archive stall. Existing safe
heartbeat and timeout limits remain. No new Mac run was dispatched here.

Prepared on 2026-10-13. Signing, upload and physical-device acceptance remain
pending. This setup uses Apple's automatic provisioning and cloud
distribution signing through an App Store Connect team API key. No Apple password,
signing certificate or private key belongs in source control.

Local validation on 2026-10-13: all five iOS configuration tests passed; Bash
syntax checks passed for the signing helper and all workflow shell steps; the
workflow YAML parsed successfully and its manual-only trigger and preflight
dependency were checked. No Mac workflow was started and no build was uploaded.

Apple portal setup on 2026-10-13: verified active paid membership; registered the
project's main and ShareExtension App IDs and shared App Group, and assigned the
group to both. Created the iOS App Store Connect record
[Coffey Table Recipes](https://appstoreconnect.apple.com/apps/6822451610/distribution)
with SKU `coffey-table-recipes-ios` and English (U.S.). Retained the existing
Sideloadly-suffixed identifier. API access requires the account owner's agreement;
the account owner accepted and submitted the agreement and Apple approved access.
With explicit owner approval, generated the `Coffey Table Recipes CI` team key
with Admin access. Verified `IOS_TEAM_ID`, `ASC_KEY_ID`, and `ASC_ISSUER_ID` were
saved in the public repository's encrypted Actions secrets; existing Firebase and
hosting secrets were retained. The browser download operation timed out after
Apple removed the one-time download control. The private key file location and
`ASC_PRIVATE_KEY` secret are not yet verified. Source push and first Mac run
remain pending. No build has been started and no tester invitation sent.

With explicit owner approval, revoked the unavailable original key and generated
a replacement Admin team key on 2026-10-13. The replacement private key's saved
location remains unverified. Updating `ASC_KEY_ID` encountered GitHub's Confirm
access prompt and was not verified as saved; complete GitHub reauthentication
before finishing the replacement key configuration. No Mac run was triggered.

Chrome recovery on 2026-10-13: after explicit approvals, revoked the second key
whose built-in-browser download was stopped, then revoked an inadvertently created
App Manager key. Generated a replacement and verified **Admin** access before and
after generation. Chrome saved its .p8 in the owner's Downloads folder; a read-only
check confirmed a nonempty private-key PEM without displaying its contents. Both
previously downloaded/unavailable keys are revoked. GitHub requires account
verification before accepting the current key ID and private-key secret. All
private-key files remain outside Git. Source push and first Mac run remain pending.

## Apple account setup

1. Sign in at https://developer.apple.com/account. Under Membership details, copy
   the 10-character Team ID.
2. Under Certificates, Identifiers & Profiles, register two explicit App IDs:
   `com.coffeytable.coffeyTableRecipes` (Coffey Table Recipes) and
   `com.coffeytable.coffeyTableRecipes.ShareExtension` (Recipe Share Extension).
   Enable App Groups on both.
3. Register App Group `group.com.coffeytable.coffeyTableRecipes`, then assign it
   to both App IDs and save. Do not change bundle IDs just because the app was
   previously sideloaded. If Apple says an identifier is unavailable, resolve
   ownership first; changing Runner also requires updating Firebase registration.
4. In https://appstoreconnect.apple.com/apps, select +, New App. Use iOS,
   name `Coffey Table Recipes`, primary language English (U.S.), Runner's bundle
   ID, and SKU `coffey-table-recipes-ios`. The SKU is an internal unique label.
   Only the main app needs an App Store Connect app record.
5. In Users and Access > Integrations > App Store Connect API, request API access
   if needed. The Account Holder must handle any required agreement. Create a
   dedicated **team** key named `Coffey Table Recipes CI`, with Admin access for
   automatic provisioning and cloud signing. This is broad developer-account
   access: the account owner must approve creating it and storing it in GitHub.
   Record Key ID and Issuer ID and download the .p8 once. Keep a secure backup.

## GitHub secrets

In `agawlbb/coffey-table-recipes` > Settings > Secrets and variables > Actions,
configure the following repository secrets. Enter secrets directly in GitHub;
do not paste the private key in chat. Retain the existing Firebase configuration.

| Secret | Value |
| --- | --- |
| `IOS_TEAM_ID` | Paid Apple membership Team ID |
| `ASC_KEY_ID` | Team API key ID |
| `ASC_ISSUER_ID` | Team API issuer ID |
| `ASC_PRIVATE_KEY` | Entire downloaded .p8 text, including BEGIN/END lines |
| `FIREBASE_CONFIG_JSON` | Existing private Firebase configuration |

The private key is restored with restricted permissions on an ephemeral runner.
Signing uses a temporary unlocked keychain. An always-run cleanup removes both
the key and Firebase configuration and deletes the temporary keychain. Apple
may create/manage certificates and profiles during automatic provisioning;
the workflow never revokes existing certificates.

## Build and upload

The `Signed iOS and TestFlight` workflow is manual-only. Publishing its source
does not start a build. Obtain explicit user approval **for each macOS run**,
including reruns. Push only with authorization, then select the intended source
branch or tag in Actions. Use a positive build number greater than previous
distributed/uploaded iOS builds; `13` is the next candidate after build `12`,
provided App Store Connect has no newer build.

Leave `upload` unchecked to export a signed App Store Connect IPA for inspection.
That IPA is not an ad-hoc device installer. Check `upload` to submit directly to
App Store Connect using Xcode's archive export. Uploading does not publish to the
App Store and does not automatically invite testers. The workflow checks secrets
on Linux before using a Mac, runs analysis/tests and verifies signatures of both
targets before export. Archive/export still needs its first real Mac validation.

After upload processing, open the app's TestFlight tab. Resolve export compliance
accurately, supply beta description/feedback contact and test instructions, and
select the build for a tester group. Internal testers must be eligible App Store
Connect users. Use an external group for family testers without developer-account
access; the first external build requires Apple's beta review. Supply reviewer
sign-in instructions/access if required. Tester invitations require explicit
authorization and actual tester addresses. Install Apple's TestFlight app on each
device, accept the invitation and install the build. Builds expire after 90 days.

## Switching from Sideloadly

Keep existing copies until the TestFlight build is ready. Verify recipes saved to
the hosted account and finish any pending import before switching. Sideloadly can
change bundle IDs, so do not assume TestFlight will preserve its app container.
Try the TestFlight installation first. If the old signing identity prevents it,
delete the sideloaded copy and retry; deletion loses local caches/settings/pending
shares. Hosted saved recipes remain available after signing in to the same account.
If both copies coexist, verify the TestFlight copy before deleting the old copy.
Stop Sideloadly auto-refresh for this app after switching.

Accept the signed build only after testing Google/email login, household/library
access and the share extension: Files PDF, Photos HEIC, text, Safari links, cold
start/resume, multiple files, explicit Save and Cancel. See
[mobile sharing](mobile-share-import.md) for the existing Sideloadly signing failure.

## References

- [Apple: create an app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
- [Apple: automatic/cloud signing with API authentication](https://developer.apple.com/videos/play/wwdc2021/10204/)
- [Apple: cloud-managed certificates](https://developer.apple.com/help/account/certificates/cloud-managed-certificates/)
- [Apple: TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

## Build-only verification (2026-10-13)

Both upload-enabled attempts are confirmed canceled (38466229058 and 38474737732). The next approved diagnostic uses upload=false. Exported packages must pass strict codesign checks for the app and share extension, match the requested build/version and Apple team, contain valid unexpired App Store profiles and signed App Group entitlements, and include a SHA-256 verification report. Local Python syntax and workflow YAML validation passed; macOS signature verification runs on the build host before artifact upload.

## Verified build outcome (2026-10-13)

Signed build-only run 38476192864 and unsigned comparison 38477465592 both completed successfully from c3b92efbf42d7542b6ca1ad4253446e445d4fdd2 using xcode-27. Signed archive/export completed and the verifier accepted version 1.3.0 build 13 for Runner and ShareExtension, including strict signatures, team, App Group and unexpired App Store profiles. Nothing was uploaded to App Store Connect or TestFlight.

Signed artifact ID: 11856970609. Downloaded artifact SHA-256 matched GitHub: ed621d05fdf0fa2f9a3a07356fbc93bd65e91fade6d91193d5f703cf1994efd3. Extracted IPA SHA-256 matched verification.json: 5181260a3e1af611192443cd0e04ef3f765cebf36eb292d257887adb6aee2862. Local package is under ignored build/verified-ios-13/package/signed/. No generated package or signing credentials are committed.

GitHub step/log reporting lagged actual execution by several minutes and showed inconsistent intermediate statuses. Logs prove the signed job built the unsigned app at 22:22 UTC and exported successfully at 22:29 UTC; the comparison built at 22:31 UTC. Signing is now demonstrated to work, but the cause of earlier stopped runs remains unproven.

## Upload the verified package

The manual ios-upload.yml workflow downloads an existing signed Actions artifact instead of rebuilding. It verifies the artifact digest/source, the IPA checksum and report, then reruns macOS signature/profile checks before using the existing App Store Connect API secret with Apple's altool. Temporary packages and credentials are removed after the job. Defaults select verified build 13 from c3b92ef. Each macOS dispatch still needs explicit user approval. Uploading does not submit an App Store release; Apple must process the build before TestFlight assignment. YAML parsing, shell syntax and diff whitespace checks passed locally.

Upload-only run 38479372780 stopped before contacting Apple because GitHub does not allow overriding its reserved GITHUB_SHA environment variable. The workflow now compares package provenance against SOURCE_COMMIT and passes the verified source explicitly to the verifier subprocess. YAML, embedded Python syntax, reserved-variable and shell syntax checks cover the correction. A new macOS upload attempt requires separate approval.

## Apple upload accepted (2026-10-13)

Corrected upload-only run 38479599513 completed successfully using workflow commit 77d0d371ace05494bf650d6c388fab4298e70fa4. The existing version 1.3.0 build 13 IPA from c3b92ef was reverified without rebuilding. Apple altool reported UPLOAD SUCCEEDED with no errors at 22:44:59 UTC, delivery UUID 8487d206-da46-499e-be83-f034f44aea8c. Apple's builds API subsequently returned build 13 with processingState VALID. Internal tester/group assignment and any required compliance responses remain separate TestFlight setup steps. No App Store release was submitted.

## Release 1.3.1 signed upload (2026-10-13)

The user separately approved signed build/upload run 38485430242 from immutable v1.3.1 source 62055747acf64dec8e513e1ff96d5c5223f3ea3d. Xcode 27 archived the app and share extension, strict signature checks passed, and direct export/upload succeeded at 23:51:29 UTC. App Store Connect received 1.3.1/build 14 with delivery ID bed37ac6-2987-47c3-b3b3-86322bda6b94. Apple finished processing. The user resolved the encryption declaration directly in Chrome; the built-in browser confirmed the warning cleared, build 14 has status Ready to Submit, and the existing Family testers internal group is assigned with two invites. No external beta review submission occurred. No public App Store submission occurred. The upload workflow intentionally skips downloadable signed-IPA artifacts; this release requested TestFlight delivery rather than an unsigned desktop package.
