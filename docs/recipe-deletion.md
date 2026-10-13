# Recipe deletion and recovery

Use the **Delete recipe** trash icon beside Edit and Share on recipe details. Confirming moves the
recipe to **Recently Deleted** for 30 days. **Undo** immediately restores it.
Open **Recently Deleted** from the left hamburger menu. The recovery screen shows the deletion date and time remaining,
supports pagination, and restores the same recipe with its details and links.

Deletion, recovery, and the recovery list require a connection. Other devices
learn about deletion when they next connect and synchronize. Devices that remain
offline can still display their previously saved copies. A confirmed deletion
removes the current device's saved copy immediately; restore saves it again.
An in-flight sync cannot overwrite a confirmed deletion with old data.

The hosted server sets the exact 30-day UTC deadline and rejects late restores.
Normal browsing, search, category counts, public sharing, and editing omit deleted
recipes. A daily backend job permanently removes expired content while preserving
past cooking records. This requires backend migration 010 and the cleanup schedule;
see the PHP repository's docs/recipe-deletion.md for deployment requirements.

Validation uses Flutter widget/offline fixtures and static analysis. Hosted API
and MySQL migration verification remain deployment checks. This change does not
publish the hosted Flutter app or create a release.

Local validation: Flutter static analysis passed, and 54 focused Flutter tests
passed across recovery, offline storage, browsing, editing and sharing.

## Localhost web publication (2026-10-12)

Rebuilt and published source commit `80694a49d29f965e2557452dfd14b884a355c799`
with `tool/publish-local-web.ps1` to the ignored XAMPP app directory. The web build
succeeded. Apache returned HTTP 200 for the app and JavaScript; the copied script
matched the generated build by SHA-256. The served JavaScript includes Delete
recipe, Recently Deleted and the 30-day recovery text, and retains coffeybean.com's
hosted API URL. Responses use `Cache-Control: no-store, max-age=0` and versioned
icon font URLs. Generated assets and local Firebase configuration remain outside
Git. No hosted Flutter app deployment or release was performed.

## Recovery controls placement (2026-10-12)

Moved Delete to a trash icon beside Edit and Share on recipe details. Moved
Recently Deleted from the recipe browser into the household's left hamburger
menu. Both locations retain the existing confirmation, Undo, restoration and
local-cache behavior. Static analysis and 16 focused recovery, household-menu
and recipe-browser tests passed. Rebuilt and published the localhost web app;
Apache returned HTTP 200 and the copied JavaScript matched the generated build.
