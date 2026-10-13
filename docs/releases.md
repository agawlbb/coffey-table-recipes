# Releases

## Release command

When the user says "create a release", review progress since the previous release, choose an appropriate version and increment its build number, validate and commit, create and push an immutable annotated tag, rebuild web/Android/unsigned iOS, explicitly dispatch hosted deployment using the release tag, save the verified Android APK in the accessible "recipe app" folder, and save the unsigned IPA on the desktop. Then remove obsolete release packages from their respective destinations, retaining unrelated files and signed packages. A tag by itself does not authorize hosted deployment; the web workflow is manual-only and requires a release tag.

`CHANGELOG.md` covers previous releases using Git history, tags, and the release records below. Every future release must update it with the version, release date, and meaningful changes since the prior release. Commit the changelog before tagging the release. Describe only changes supported by the project history.

## 1.3.0 — recipe recovery and simpler editing

Version `1.3.0+12`, tagged `v1.3.0`, adds recipe deletion, Undo and 30-day recovery, offline cache consistency, simplified import/editing with visible categories, and alphabetical browsing. Supporting backend migration 010 and scheduled expiry cleanup were already deployed and verified. Web and Android are built as part of the release; unsigned iOS is separately dispatched only after explicit approval, using the public repository's standard `xcode-27` runner. GitHub documents standard hosted runner usage as free for public repositories; this does not replace the project's per-run approval requirement or verify account billing independently.

Verified on 2026-10-12: analysis passed, all 124 Flutter tests passed, and five iOS configuration checks passed. Android release compilation succeeded; metadata confirms 1.3.0/build 12 and the APK copy hash matched in the configured recipe app folder. Obsolete numbered 1.2.0 APK was removed after verification. Ubuntu web deployment [38332015428](https://github.com/agawlbb/coffey-table-recipes/actions/runs/38332015428) passed source and asset verification; hosted metadata identifies release commit `69065e8`. The built-in browser loaded the collection and authenticated Recently Deleted list without deleting or restoring a recipe.

The user separately approved one iOS run. Public-repository run [38332017587](https://github.com/agawlbb/coffey-table-recipes/actions/runs/38332017587) succeeded on standard `xcode-27` in 8m49s, including native compilation and unsigned packaging; simulator jobs were skipped. GitHub's [runner documentation](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) lists this standard runner and free public-repository use. The run usage page reports runtime, without a priced charge field. The app and embedded share extension both confirm 1.3.0/build 12. The unsigned IPA is on the desktop and its copy hash matched. A final read-only check confirmed no obsolete numbered unsigned desktop IPAs; signed and unrelated files were retained. Signing, installation and physical-device acceptance remain user-managed.

## 1.2.0 — web and Android photo editing release

Version `1.2.0+11`, tagged `v1.2.0`, adds local recipe photo crop, rotation, flip and resize tools and includes the sanitized AGPL public-source publication. Build 11 follows the distributed iOS development build 10. Only web and Android are built at the user's request; no macOS workflow or iOS package is produced. The hosted app is explicitly deployed using the release tag, and the verified APK is saved in the configured recipe app destination. Previous iOS packages are retained.

Verified on 2026-10-12: Flutter analysis passed and all 110 tests passed, including photo transformation and editor coverage. Android release compilation succeeded; package metadata confirms 1.2.0/build 11 and the APK copy hash matches in the configured recipe app folder. Public-repository Ubuntu deployment [38313238174](https://github.com/agawlbb/coffey-table-recipes/actions/runs/38313238174) passed build/tests, source metadata and asset verification. Hosted version metadata identifies release commit `75836e0`, and the built-in browser loaded the authenticated recipe collection. Only the web deployment workflow ran for this release commit. No macOS or iOS workflow was dispatched. No obsolete numbered APKs were found during cleanup; unrelated files and iOS packages were retained.

## iOS-only development builds

The iOS workflow can build an explicitly selected branch without creating a release
tag. Leave `release_tag` empty and optionally set a positive `build_number` to
distinguish the development IPA from the last release. This builds unsigned iOS
only; the tag-triggered release path and hosted web remain separate. Upload names
use the source commit when no release tag is supplied, so branch names containing
slashes are safe. Push the build branch only with the user's authorization.

### 1.1.1 build 10 — free-account share importer

Built on 2026-10-12 from `cd75d29` on the authorized
`codex/ios-free-account-share-build` branch, with the iOS build-number override
set to 10 and no new release tag. The app includes the self-contained share-sheet
importer without App Groups and refreshes recipes when returning to iOS. This is
an iOS-only development build; the version in pubspec remains 1.1.1+9.

Workflow [38233730579](https://github.com/agawlbb/coffey_table_recipes/actions/runs/38233730579)
passed analysis, all 110 Flutter tests, five iOS configuration checks, eight
extension-flow tests, native Xcode compilation and unsigned IPA packaging. The
initial build failed embedded-extension validation because a custom top-level
Resources directory is reserved by iOS; the successful source uses ShareUI and
includes a regression check for that folder name.

Downloaded artifact 11739777041 matched GitHub's artifact checksum. Runner and
ShareExtension metadata both confirm 1.1.1/build 10. All four importer UI assets
match the committed source, Firebase client configuration is present, the compiled
extension contains the hosted API bridge, and neither target declares AppGroupId.
The package contains no embedded provisioning profile. The verified IPA was saved
as `C:\Users\developer\OneDrive\Desktop\CoffeyTableRecipes-1.1.1-build10-unsigned.ipa`;
its SHA256 and desktop-copy hash are
`0503deb23fd273387026c7c54ce3f8ab02a82d455ec115c0beffc86c673f9c1f`.
Signing and physical-device share-sheet execution remain to be verified. The
previous build 9 IPA was retained.

## 1.1.1 — iOS-only startup and document-opening patch

Version `1.1.1+9`, tagged `v1.1.1`, fixes share errors opening Add recipe on ordinary launches and adds a persistent app-sandbox file-opening inbox for PDFs, images and text. Only unsigned iOS is built and delivered to the desktop at the user's request; Android and hosted web stay on 1.1.0. Signed-device file delivery still requires validation; the App Group share extension remains dependent on its signing entitlements.

Verified on 2026-10-11: iOS workflow run `38192709614` passed analysis, all 106 Flutter tests, five iOS configuration checks, native Xcode compilation and unsigned IPA packaging. The app and embedded share extension both confirm 1.1.1/build 9, and the packaged app declares document-opening support. The unsigned IPA was copied to the desktop and its copy hash matched. Obsolete numbered unsigned desktop IPAs were eligible for removal only after replacement verification; signed and unrelated files were retained. No Android build or hosted deployment was performed. Signed-device normal-launch and file-opening tests remain pending.

## 1.1.0 — import photo review and mobile sharing refinements

Version `1.1.0+8`, tagged `v1.1.0`, adds suggested source food photos/crop review, typed import categories, visible persistent iOS share handoff, readable duration editing, and simplified recipe tiles. Web, Android and unsigned iOS use the same version and build number. For this release only, the user requested that only `CHANGELOG.md` be copied to the desktop: Android remains in `G:\My Drive\recipe app`, and the unsigned IPA remains in the ignored project build folder. Existing desktop packages are retained.

Verified on 2026-10-11: analysis passed, all 103 Flutter tests passed, and four iOS configuration tests passed. Android release compilation succeeded; its APK metadata confirms 1.1.0/build 8 and the destination copy hash matched. Web deployment run `38191055363` published and verified release commit `ad7dbde`; public metadata confirms 1.1.0/build 8, and the built-in browser loaded the recipe collection after a connection retry. iOS run `38191054507` successfully built the app and share extension; both IPA metadata versions confirm 1.1.0/build 8. The unsigned IPA is retained at `build/ios-release-1.1.0/CoffeyTableRecipes-1.1.0-build8-unsigned.ipa`. The desktop changelog copy hash matches the committed changelog. Only numbered obsolete APKs were eligible for cleanup in the Android destination; unrelated test files and desktop mobile packages were retained. Signing and physical-device checks remain user-managed.

## 1.0.0 — first usable release with recipe import

Version `1.0.0+7`, tagged `v1.0.0`, marks the user's first usable release. It adds AI-assisted recipe import from text, descriptions, websites, uploads and camera photos, clarification and editor review before saving, mobile incoming shares, optional AI imagery, and ingredient/category/editor refinements. Web, Android and unsigned iOS share the version and build number. Android retains its existing signing identity for upgrade compatibility. iOS signing, App Group provisioning for both Runner and ShareExtension, and physical device share-sheet checks remain user-managed.

Verified on 2026-10-11: analysis passed and all 96 Flutter tests passed. iOS configuration tests passed (three after adding the build-order regression). Supporting backend HEAD deployed successfully in run `38183194195`. Android release metadata confirms 1.0.0/build 7 and the APK copy hash matched in `G:\My Drive\recipe app`. Web run `38185606646` published and verified release commit `13145b1`; the built-in browser loaded the collection and Add recipe screen without submitting AI input or saving data. Initial iOS compilation found a dependency cycle; corrected workflow run `38185920984` rebuilt immutable `v1.0.0` app source with extension embedding moved before Flutter thinning. Its unsigned IPA contains ShareExtension, and both app and extension metadata confirm 1.0.0/build 7. The IPA is on the desktop; old numbered 0.5.0 packages were removed after verification. The separately named share-import test APK was retained after automatic approval review rejected its deletion. Device signing and physical share-sheet testing remain pending.

## 0.5.0 — recipe editing, sharing, and resumable downloads

Version `0.5.0+6`, tagged `v0.5.0`, adds the complete recipe editor with device photos and step actions, database-ID recipe link sharing, and resumable full recipe-text downloads with offline readiness checks. Supporting backend changes are already hosted. Web, Android and unsigned iOS use the same version and build number. The initial historical changelog was created from prior release records and Git history before tagging this release.

Verified on 2026-10-11: Flutter analysis passed and all 77 tests passed. Android release compilation succeeded; the APK was copied to `G:\My Drive\recipe app`, its copy hash matched, and its metadata confirms 0.5.0/build 6. Hosted deployment run `38144164128` passed version and asset verification; public metadata identifies release commit `932e943` and the built-in browser loaded the recipe collection. iOS run `38144162621` successfully built the unsigned IPA using Xcode 26.3; its metadata also confirms 0.5.0/build 6. The IPA was saved on the desktop, replacing the obsolete 0.4.0 unsigned IPA. No obsolete APKs were present in the Android destination. Signing and device installation remain user-managed.

## 0.4.0 — offline recipe library and browsing

Version `0.4.0+5`, tagged `v0.4.0`, adds an offline mobile recipe library and recent-photo caching, scoped recipes below distinct category cards, backend-delivered verification emails, and administration of Firebase-only accounts. The existing hosted verification backend is already deployed; this release rebuilds and distributes the app without database or backend changes. All three platforms share this version and build number; iOS is unsigned for user-managed signing.

The connectivity plugin requires the iOS 26 SDK. The iOS workflow selects Xcode 26.3 and supports manually rebuilding an existing release tag with updated workflow tooling, preserving the tag and application source.

Verified on 2026-10-11: analysis passed and all 60 Flutter tests passed. Android release compilation succeeded after regenerating plugin registration following tests. Web deployment run `38136744689` passed source metadata and asset verification; public metadata identifies `a6ded16`, version 0.4.0/build 5, and browser category browsing succeeded after a connection retry. Initial iOS compilation failed with the older SDK; corrected run `38137001260` checked out the unchanged `v0.4.0` source and successfully produced the unsigned IPA using Xcode 26.3. APK and IPA metadata both confirm version 0.4.0/build 5. Both packages were saved on the desktop, and the obsolete 0.1.0 APK found there was removed after replacement verification. Signing and on-device installation remain user-managed.

## 0.3.0 — email verification and administration

Version `0.3.0+4`, tagged `v0.3.0`, adds a dedicated email verification screen, explicit resend and refreshed verification claims before loading household invitations. Administration supports deleting accounts and unlinked table people. Android, web and unsigned iOS packages share this version and build number. The release tag publishes the hosted web app and builds iOS through GitHub Actions; signing and device installation remain user-managed.

Release verification on 2026-10-10: Flutter analysis passed and all 39 tests passed. Android release APK metadata confirms version 0.3.0/build 4. Hosted deployment run `38085019825` passed publication and asset verification; public version metadata identifies release commit `4ee5b75`, and the browser loaded recipe categories after a connection retry. iOS run `38085019826` built and packaged the unsigned IPA successfully. Both mobile packages were saved to the user's desktop; signing and on-device installation are pending.

## 0.2.0 — household invitations

Version `0.2.0+3`, tagged `v0.2.0`, adds household invitation dialogs, invitation responses after login, retry handling and duplicate submission protection. It targets the hosted coffeybean.com backend with the previously deployed invitation support.

Android release APK and unsigned iOS release IPA use the same version and build number. The iOS package is built by GitHub Actions for user-managed signing and installation. Validate with Flutter analysis and the complete test suite before distributing the builds. Generated packages and private Firebase configuration remain outside Git.

The initial demonstration is **0.1.0+1**, tagged `v0.1.0` in the app and backend repositories. It uses the hosted coffeybean.com API.

`pubspec.yaml` is the authoritative app version: `major.minor.patch+build`. Before 1.0, minor versions add demonstration features and patch versions fix bugs. Increment the integer build number for every distributed build. At the user's request, 1.0.0 marks the first usable release with recipe import. Never move an existing release tag.

All platforms in a release use the same version and build number. Android demonstrations use the existing debug signing identity. iOS Actions packages an unsigned release IPA for inspection; it is not directly installable. Current paid-account signing uses Apple-native archive/export with separate app and extension profiles and App Group membership (see mobile-share-import.md). Firebase iOS registration and device testing are required before calling iOS ready.

Validate with `flutter analyze` and `flutter test`, build web and APK with the ignored `config/firebase.local.json`, then commit and create an annotated version tag. Push the commit and tag. The tag triggers the iOS workflow; its private artifact expires after 30 days, so keep a local copy.

The web entry is `/CoffeyTableRecipes/`, with assets in `/CoffeyTableRecipes/app/`. `app/version.json` records the version, build and source commit for deployment verification. Credentials, generated artifacts, signing identities and local Firebase configuration remain outside Git.

## 0.1.0 — initial demonstration

Household authentication, recipe categories and browsing, recipe details, cooking mode and navigation breadcrumbs. Hosted backend remains selected; no database or API changes are part of this release.

### iOS build 2

The iOS follow-up uses `0.1.0+2` and tag `v0.1.0-ios.2`; the initial `v0.1.0` tag remains immutable. Web and Android build 1 remain the published initial demo. The iOS workflow requires its Firebase client values and inserts the Google callback URL scheme during the build, keeping local client configuration outside source control. Sideloadly signing and on-device authentication must be verified separately.
