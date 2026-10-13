# Signed iOS builds and TestFlight

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
