# Releases

## Release command

### Required native link verification

Native shared-link routing is not complete until the domain-root association
files are published and verified. The Flutter web deploy does not publish these
files. Before marking a release complete, inspect the delivered APK certificate
with `apksigner verify --print-certs`, then run
`python tool/verify-app-links.py --fingerprint ACTUAL_CERTIFICATE_SHA256`.
The default fingerprint belongs to the APK delivered for 1.6.0; Play App Signing
may require a different certificate from the upload key. The web deployment
workflow now fails before building if the configured Android association is
missing or mismatched. Update the checker when signing changes.

For iOS, separately verify the signed app's Associated Domains entitlement,
provisioning, and matching Apple application identifier in the domain-root AASA
file. Do not treat the Android check as iOS verification. Test both cold/warm
shared-link opening on installed devices; report unperformed device checks.

If iOS AASA is missing or needs repair, the manual Ubuntu-only `ios-association.yml`
workflow uses the existing deployment token and signing team to publish only the
app's association. It verifies the domain document root, preserves existing JSON
entries and MIME rules, and requires a public HTTPS 200 JSON response without
redirects. It does not build an app or change Apple distribution settings.

The source for the domain-root Android file lives in the backend repository at
`hosting/assetlinks.json`. Deploy it to `coffeybean.com/.well-known/assetlinks.json`,
preserving any entries for other apps. This can be repaired independently of an
app build. Android may retain failed verification until it retries; check Open
by default / Open supported links on an already installed phone if necessary.

### Release execution

Android link repair after 1.6.0/1.6.1 on 2026-10-16: the domain-root
`assetlinks.json` was still 404 because only web assets had been deployed.
Published the association for the verified APK certificate. The public checker
and its three regression tests passed; Android re-verification reported the
domain verified with this app as owner. A normal, unforced link intent opened
recipe 14 directly in the installed emulator app and displayed its public
recipe screen. This was a warm-start check, not physical-phone/cold-start
acceptance. No new app build or reinstall was needed. The separate iOS
association repair and release validation are recorded under 1.6.1 below.

When the user says "create a release", review progress since the previous release, choose an appropriate version and increment its build number, validate and commit, create and push an immutable annotated tag, rebuild web/Android/signed iOS, explicitly dispatch hosted deployment using the release tag, save the verified Android APK in the accessible "recipe app" folder, and upload signed iOS to TestFlight. Requested iOS runs need no separate approval; other macOS runner builds still require explicit approval. Verify Apple processing and internal distribution, observing the France exclusion policy. Then remove obsolete release packages from their respective destinations, retaining unrelated files and signed packages. A tag by itself does not authorize hosted deployment; the web workflow is manual-only and requires a release tag.

`CHANGELOG.md` covers previous releases using Git history, tags, and the release records below. Every future release must update it with the version, release date, and meaningful changes since the prior release. Commit the changelog before tagging the release. Describe only changes supported by the project history.

## 1.8.1 — shopping list checking and presentation

Version `1.8.1+25`, tagged `v1.8.1`, is the explicitly requested patch release. Both repositories contain only main locally and on GitHub; project branches and tags were pushed before release preparation. Changes since 1.8.0 add tap-to-check shopping rows, a separate completed-items group that preserves departments, larger bold headings, assigned-item indentation and regression coverage. Native code, dependencies, encryption behavior and signing identities are unchanged; production APNs, actual signed universal-link identity and distribution profiles remain gated before upload. France exclusion is retained. Platform and validation results follow as verified.

Local validation on 2026-10-18: analysis passed, all 327 Flutter tests passed, all 13 iOS configuration/distribution checks passed, both Apple JWT/status tests passed and diff whitespace checks passed. The requested release tag was verified unused. Backend source remains synchronized at `6934f4592a6ab3b9b5778ee60b4e568f6e0ab40d`; no backend runtime changes or migrations are included in this patch.

Web deployment [39159414813](https://github.com/agawlbb/coffey-table-recipes/actions/runs/39159414813) succeeded in 3m31s, including analysis/tests, compilation and hosted asset verification. Public metadata confirms 1.8.1/build 25 from immutable release commit `b37537d211b39f81f0217f055390abd2373b630f`; backend health is OK.

Android release compilation succeeded in 138.6 seconds. Package metadata confirms 1.8.1/build 25. Delivered `G:\My Drive\recipe app\CoffeyTableRecipes-1.8.1-build25.apk` matches source SHA-256 `7e6e225b0f61535de7551c184c2594c1b3113825b54c2e2cfad319fa6ba98a6c`. Signature verification passed and actual certificate `F8:DE:93:3F:14:B9:BB:4B:31:91:A9:4A:ED:C8:63:79:72:C5:AB:22:45:65:F6:AB:D7:80:8F:80:38:D1:20:97` matches the hosted association. Removed the obsolete numbered build 24 APK only after replacement checksum verification.

Installed the verified release on the existing headless Pixel 8/API 36 emulator with data preserved. Android reports the domain verified. Unforced HTTPS VIEW intents opened MainActivity cold and delivered to the running activity warm; the UI hierarchy confirmed Chinese Orange Chicken (recipe 14). Installed metadata confirms 1.8.1/build 25. The emulator started for this check was stopped afterward. Physical-device push/alarm and iPhone link checks were not performed.

Initial iOS run `39159417126` passed analysis, Flutter tests and all 13 iOS checks but failed automatic archive provisioning because Apple reached its development-certificate limit; no iOS upload occurred. Read-only certificate audit `39160467546` identified temporary API development certificate `UH5NHSV67V`, SHA-1 `02CA6CF204A5A828CE04B345C76B53265EDB59DA`, matching the exact codesign identity in the successful 1.8.0 CI log. Its private key was removed with that runner's temporary keychain. Prepared guarded replacement tooling and reusable identity import; certificate revocation and encrypted signing-secret storage await explicit owner approval. Personal and distribution certificates have not been modified. The release tag remains unchanged and web/Android remain delivered.

The owner subsequently approved that exact certificate replacement, encrypted GitHub secret storage and iOS retry. Operation [39160933165](https://github.com/agawlbb/coffey-table-recipes/actions/runs/39160933165) revoked only `UH5NHSV67V` and issued reusable development certificate `MUX6GX7BLL`, SHA-1 `BA5B3DCFC67E3C2CD132D8BE6296129DD70D07B4`. Public-key binding to the locally generated CSR was verified before packaging. Only the public CSR/certificate reached the public workflow/artifact; private key and password were transferred directly to encrypted repository secrets `IOS_DEVELOPMENT_CERT_P12` and `IOS_DEVELOPMENT_CERT_PASSWORD`, without command-line values or log output. The P12 includes Apple's matching G3 intermediate. Recovery run `39161086200` passed Ubuntu secret preflight and Mac keychain import using the original `v1.8.1` checkout; temporary local secret copies were then removed. Personal and distribution certificates were retained. Signing recovery checks passed two focused guard/CSR tests and YAML/13 shell-block syntax validation. Final upload and processing results follow after verification.

## 1.8.0 — household shopping lists and mobile timer mirroring

Version `1.8.0+24`, tagged `v1.8.0`, releases main in both repositories. Local and GitHub branch inspection found only main when this release began. All local branches and tags were synchronized before preparation. Build 23 was the earlier Android timer-sync test package, so this release uses build 24. Features include household shopping lists and department memory, scoped list caching and visible refresh, external synchronization requests, mobile timer mirroring and shared navigation/presentation refinements.

Firebase Messaging and shared preferences are new dependencies. Review found standard platform/Firebase transport and storage, with no added non-exempt encryption; the existing declaration and France exclusion policy are retained. The iOS release exports a distribution IPA, verifies actual signatures/profiles, production APNs, application identity and hosted universal-link association before the existing Xcode upload. Physical-device push delivery, background timing and audibility require device acceptance and are not established by compilation or FCM acceptance. Platform results follow as verified.

Local validation on 2026-10-18: Flutter analysis passed and all 326 unit/widget tests passed. The first full run found a stale editor regression expecting duplicate recipe titles after the intentional app-bar-only change. Updated it to require one title in the app bar; the complete suite then passed. All 13 iOS configuration/distribution checks, two Apple JWT/status checks, signing-shell syntax and Python syntax checks passed. Backend main `6934f4592a6ab3b9b5778ee60b4e568f6e0ab40d` is already pushed; supporting timer/shopping migrations and hosted deployments were performed and verified during feature work, so no one-time migration is rerun for this release.

Web deployment [39152414619](https://github.com/agawlbb/coffey-table-recipes/actions/runs/39152414619) succeeded in 3m25s, including analysis/tests, compilation and hosted asset verification. Public metadata confirms 1.8.0/build 24 from immutable release commit `be111854107292beddc6f8863f79d9b1dcf351f1`. Backend deployment `39148973036` succeeded from runtime source `8ec35404908a745cc549735580e8c3164d9c124b`; live health is OK and unauthenticated account access returns 401.

Android release compilation succeeded in 218.7 seconds. Package metadata and the installed emulator confirm 1.8.0/build 24. Delivered `G:\My Drive\recipe app\CoffeyTableRecipes-1.8.0-build24.apk` matches source SHA-256 `75ac7ec0932c55596f3d1a4a51188a71434e8ded24d21bb05a283fcdadb74e11`. APK signature verification passed, and actual certificate `F8:DE:93:3F:14:B9:BB:4B:31:91:A9:4A:ED:C8:63:79:72:C5:AB:22:45:65:F6:AB:D7:80:8F:80:38:D1:20:97` matches the public association. No obsolete numbered release APK remained in the destination; the separate build 23 timer-sync test package was retained.

Started the existing Pixel 8/API 36 emulator headlessly, installed the verified release while preserving its data, and requested ordinary domain re-verification. Android reports `coffeybean.com: verified`. Unforced HTTPS VIEW intents launched MainActivity cold and delivered to the running instance warm; visual inspection confirmed Chinese Orange Chicken (public recipe 14) with its recipe content. The generic package-resolution query separately returned ResolverActivity, so acceptance evidence is the actual unforced cold/warm starts and displayed recipe, not that query. No link preference was forced. The emulator started for this check was stopped afterward. This verifies emulator link routing, not physical-device push delivery or alarm audibility.

Signed iOS run [39152416625](https://github.com/agawlbb/coffey-table-recipes/actions/runs/39152416625) succeeded in 17m35s. Analysis, Flutter tests, all 13 iOS configuration/distribution checks, native Swift compilation, provisioning, archive, strict app/extension signatures and distribution IPA verification passed. Xcode reported `ARCHIVE SUCCEEDED` at 18:15:39 UTC on October 18, local distribution export succeeded at 18:18:16 UTC, and the verifier confirmed production APNs in Runner's actual signed entitlements and distribution profile plus the hosted AASA against its signed application identity and shared-recipe route. It also verified all three target versions/builds, app groups, exempt-encryption metadata and App Store Connect profiles. The locally verified distribution export SHA-256 is `d1ced06aa6fe6f5c37044fc66d02ae1e0a1c043b821e3e9da21e08af8cc3c9e7`; Xcode then performed its upload export from the same archive and reported `Upload succeeded` / `EXPORT SUCCEEDED` at 18:21:14 UTC. No iOS IPA was published as a workflow artifact or copied to the desktop. Physical iPhone universal-link and push/alarm acceptance checks were not performed.

Apple verification [39153850892](https://github.com/agawlbb/coffey-table-recipes/actions/runs/39153850892) succeeded: version 1.8.0/build 24, Apple build ID `c443b679-78c9-4677-ad26-45afe8bf5616`, processing `VALID`, `usesNonExemptEncryption=false`, internal state `IN_BETA_TESTING`, and existing `Family testers` group attached. No testers or territories were added; France exclusion is retained. All three requested platforms are delivered, with physical-device timer delivery/audibility and iPhone link acceptance explicitly outstanding.

## 1.7.0 — household favorites, blank recipes and import methods

Version `1.7.0+22`, tagged `v1.7.0`, releases main only; the user explicitly requested leaving other branches intact. Both repositories' local branches and tags were pushed before release preparation. This release adds household favorites and combined filters, blank recipes and import into placeholders, alternative-method review and linked variations, ingredient reordering/deletion and presentation refinements. No encryption dependencies or entitlements changed from 1.6.1; the exempt-encryption declaration and France exclusion policy are retained. Android is delivered to `G:\My Drive\recipe app`, web is explicitly published from the tag, and signed iOS is uploaded to TestFlight. Platform and validation results are recorded below as verified.

Local release checks on 2026-10-17: analysis passed, all 290 Flutter tests passed, seven iOS configuration checks passed, three Android association regression checks passed and both Apple JWT/status tests passed. The first full run exposed a seven-pixel variation-menu overflow after adding favorite controls. Constraining the menu to the remaining action-row width fixed it; the existing navigation/layout regression and complete suite then passed. Backend deployment `39061791888` succeeded from main commit `037b053d8ccd26729c81f8c51fb9cba991467328`, including PHP/Python checks. No one-time migration was rerun.

Web deployment [39062224114](https://github.com/agawlbb/coffey-table-recipes/actions/runs/39062224114) passed analysis/tests, compilation, deployment-tool tests and hosted asset verification in 3m27s. Public metadata confirms version 1.7.0/build 22 from release commit `a877c6390b7be43bc525016a6c878efc216224e8`. Backend health is OK; the public recipe 14 share page returns 200 and unauthenticated account access returns 401.

Android release compilation succeeded in 196 seconds. Package metadata confirms version 1.7.0/build 22 and the existing app identifier. Delivered `G:\My Drive\recipe app\CoffeyTableRecipes-1.7.0-build22.apk` matches source SHA-256 `0ce2099565577763a25d21f2be7cfb07103cecef2036930ed89bd3c284c869df`. Strict APK signature verification passed; certificate SHA-256 `F8:DE:93:3F:14:B9:BB:4B:31:91:A9:4A:ED:C8:63:79:72:C5:AB:22:45:65:F6:AB:D7:80:8F:80:38:D1:20:97` matches the hosted domain-root Android association. Obsolete build 21 was removed after replacement checksum verification. No connected Android device or emulator was available for OS link-opening tests.

Signed iOS run [39062226300](https://github.com/agawlbb/coffey-table-recipes/actions/runs/39062226300) succeeded in 20m3s, including analysis, Flutter tests, seven configuration checks, native compilation, provisioning, archive and strict signatures for Runner, ShareExtension and TimerWidget. Xcode reported `ARCHIVE SUCCEEDED` at 19:38:38 UTC and `Upload succeeded` / `EXPORT SUCCEEDED` at 19:42:58 UTC on October 17. Archive signing entitlements show the expected `com.coffeytable.coffeyTableRecipes` application identifier under the configured signing team and `applinks:coffeybean.com`. The domain-root AASA was independently verified against that identity and `/CoffeyTableRecipes/share.php`, requiring HTTPS 200, JSON MIME and no redirect. No association repair was needed. Physical iPhone cold/warm link checks were not performed.

Apple verification [39063785892](https://github.com/agawlbb/coffey-table-recipes/actions/runs/39063785892) passed: version 1.7.0/build 22, Apple build ID `ce2b2f94-1992-4665-a2f9-5e1eb41f132d`, processing `VALID`, `usesNonExemptEncryption=false`, state `IN_BETA_TESTING`, and existing `Family testers` group attached. The earlier read-only checker `39063178613` exhausted its polling window before the uploaded build appeared; no second app build was needed. No testers or territories were added, and France exclusion is retained. No unsigned desktop IPA was delivered. Concurrent backend documentation-only commit `d636d0e` was also synchronized without changing deployed runtime source or the immutable app tag; unrelated detached worktree changes were preserved.

## 1.6.1 — timer widget App Store metadata correction

Version `1.6.1+21`, tagged `v1.6.1`, completes all three platforms after the initial 1.6.0 iOS upload was rejected for missing `CFBundleDisplayName` in TimerWidget. The widget now declares its display name; source configuration checks cover all three bundles, and archive/export tooling checks actual bundle metadata before upload. The signed IPA verifier checks it too. No Dart application behavior changed from 1.6.0. Web and Android are rebuilt at 1.6.1/build 21 for alignment. The immutable 1.6.0 tag remains unchanged. Native compilation, signing and provisioning of all three targets succeeded in the earlier run; only Apple's upload metadata validation rejected it.

Web deployment [38995426326](https://github.com/agawlbb/coffey-table-recipes/actions/runs/38995426326) succeeded. Public metadata confirms version 1.6.1/build 21 and immutable release commit `16fe8e9e72a570fb1815bb77b1914d5e2209775b`. Android release compilation succeeded; package metadata confirms 1.6.1/build 21. The delivered `G:\My Drive\recipe app\CoffeyTableRecipes-1.6.1-build21.apk` matches source SHA-256 `6f60a581b35ba9eef2bb51ad6a5b66fa163dd0a459edf38aa3e4f4272d7e315b`. The obsolete numbered build 20 package was removed only after verification, retaining unrelated packages.

The actual APK certificate matches the hosted Android association (`F8:DE:93:3F:14:B9:BB:4B:31:91:A9:4A:ED:C8:63:79:72:C5:AB:22:45:65:F6:AB:D7:80:8F:80:38:D1:20:97`). iOS association deployment [38995992032](https://github.com/agawlbb/coffey-table-recipes/actions/runs/38995992032) published the previously missing domain-root AASA, preserving other entries and verifying the configured signing-team/bundle identifier, HTTPS 200, application/json and no redirect. The association covers `/CoffeyTableRecipes/share.php`. Tooling was committed after tagging without changing the immutable release source. Physical iPhone cold/warm link checks were not performed; browser rendering was unavailable in this session.

Signed iOS run [38995428244](https://github.com/agawlbb/coffey-table-recipes/actions/runs/38995428244) succeeded in 15m50s, including analysis, all 248 Flutter tests, seven configuration checks, native compilation, automatic provisioning, archive and strict signatures for Runner, ShareExtension and TimerWidget. The archive's signing entitlements show `com.coffeytable.coffeyTableRecipes` under the same configured signing team as AASA, with `applinks:coffeybean.com`. Xcode reported `ARCHIVE SUCCEEDED` at 02:45:20 UTC on October 17 (October 16 locally), verified display names in all bundles, then `Upload succeeded` and `EXPORT SUCCEEDED` at 02:49:53 UTC. No additional unsigned IPA was delivered.

Apple API verification [38996172143](https://github.com/agawlbb/coffey-table-recipes/actions/runs/38996172143) succeeded: version 1.6.1/build 21, Apple build ID `6e5490ec-708d-4f03-8e3e-e782f6dd6eb9`, processing `VALID`, `usesNonExemptEncryption=false`, internal state `IN_BETA_TESTING`, and existing `Family testers` group attached. No testers or distribution territories were added; the France exclusion policy is retained. Both merged feature branches were verified absent locally and on GitHub. Release validation is complete apart from the explicitly unperformed physical-iPhone link acceptance checks.

## 1.6.0 — shared recipes and native cooking timers

Version `1.6.0+20`, tagged `v1.6.0`, merges app branch `feature/shared-recipes-native-timers` and corresponding backend branch `feature/shared-recipes-public-reads` into their respective main branches. Build 20 follows development packages through build 19. The release includes public canonical recipe reads and household attachment, guarded shared editing, family navigation, native mobile alarms, app-wide timer controls and tone previews, the iOS timer widget, responsive/keyboard fixes, menu refinements and menu version display. Web is explicitly deployed, Android goes to `G:\My Drive\recipe app`, and signed iOS is uploaded to TestFlight. Existing exempt-encryption declarations and France distribution exclusion remain. Physical-device alarm audibility, permissions, lifecycle/Live Activity behavior and OS link association require device acceptance; unit tests or compilation do not establish those guarantees. The backend migrations were already applied and verified before this merge; no replay of the one-time migration job is requested.

Local verification: analysis passed, all 248 Flutter tests and seven iOS configuration checks passed. Backend fixture checks passed: 18 shared recipe, 97 canonical variation relationship and six migration checksum assertions. App merge `a260496` and backend merge `e859ca7` preserve both histories. Both feature branches were confirmed merged, then deleted locally and on GitHub after main was pushed. The backend workflow's apparent modification was stat-only: its normalized content matched the committed blob and refreshing its index cleared the status without changing source. Backend validation record commit `beb52d5` was pushed independently. Platform delivery results follow below.

Android release compilation passed; package metadata confirms 1.6.0/build 20. The APK at `G:\My Drive\recipe app\CoffeyTableRecipes-1.6.0-build20.apk` matches SHA-256 `f0c24eed3706834dabd23be3342cbfa6796bf501479c47b8814feceb5d956949`. No obsolete numbered release APKs were present; separately named test/debug packages and unrelated files were retained. Web deployment [38994336167](https://github.com/agawlbb/coffey-table-recipes/actions/runs/38994336167) passed tests, compilation and hosted source/asset verification. Public metadata confirms release commit `449f504f3f2885ff055ca2a2c0a897ceb4d2c141`, version 1.6.0/build 20. Backend health, unauthenticated recipe 14 and share-page reads passed; unauthenticated `/me` returned 401. Browser rendering could not be checked because no browser was available in this session.

Backend main deployment initially failed in an outdated in-memory parent-category fixture before publishing. Fixture correction `b96a576` added canonical recipe memberships without changing production logic. All 17 PHP deployment fixture scripts passed locally afterward, and corrected deployment [38994460644](https://github.com/agawlbb/coffey-table-recipes-server/actions/runs/38994460644) succeeded. No one-time shared-recipe migration was rerun. A separate Ubuntu-only read-only Apple status workflow was added after tagging; local JWT/status tests passed and verification of prior release 1.5.0/build 16 succeeded in run `38994638819`. This tooling does not change the immutable app tag or create a package.

Signed iOS run `38994337950` passed analysis, all 248 Flutter tests, seven configuration checks, native compilation and strict signatures for Runner, ShareExtension and TimerWidget. Its archive succeeded, but Apple rejected export/upload because TimerWidget lacked the required display name. No TestFlight delivery is claimed for 1.6.0/build 20. The corrective release is 1.6.1/build 21.

## 1.5.0 — faster browsing and focused recipe review

Version `1.5.0+16`, tagged `v1.5.0`, adds cached type-ahead search, immediate cached category text, linked-photo prefetching, focused recipe editing with ingredient groups and quantity handling, imported-category preservation, clearer import failures, shared parent-category administration with AI covers, and recipe layout refinements. Supporting backend import/grouping/category changes are recorded separately. The user requested pushing all local changes and releasing all three platforms. Requested iOS builds no longer need separate approval. Web is explicitly published, Android goes to `G:\My Drive\recipe app`, and signed iOS is uploaded to TestFlight with the existing exempt-encryption declaration and France exclusion policy. Verification results follow as platforms complete.

Local validation on 2026-10-16: Flutter analysis passed, all 228 Flutter tests passed, all five iOS configuration checks passed, and diff whitespace checks passed. App dependencies are unchanged since 1.4.0; the existing exempt-encryption declaration is retained. All pre-release local commits were pushed in both repositories before version tagging.

Backend deployment [38920295003](https://github.com/agawlbb/coffey-table-recipes-server/actions/runs/38920295003) succeeded from `deed3b01d29541f611184bd9c4439728db090775`. Android release compilation passed; metadata confirms 1.5.0/build 16, and `G:\My Drive\recipe app\CoffeyTableRecipes-1.5.0-build16.apk` matches source SHA-256 `112b87aabbecb6a0fd69ff03aa0d8a79718435356b6cb29c23aa8f30b9dc2bac`. The obsolete numbered 1.4.0/build 15 APK was removed after replacement verification. Unrelated files were retained. Web deployment [38920656416](https://github.com/agawlbb/coffey-table-recipes/actions/runs/38920656416) passed analysis/tests, compilation and hosted asset verification. Public metadata confirms 1.5.0/build 16 from release source `63c95c09bbcf19d16b0c718c278588b65ce5f001`; backend health passed. The authenticated collection loaded after a session reload resolved an initial household connection error. Live type-ahead search for `muffin` returned Bran Flax Muffins and the ingredient-matching Caramelized Onion and Cornbread Stuffing without explicit search submission; clearing search restored categories. No recipe data was changed.

Signed iOS run [38920660514](https://github.com/agawlbb/coffey-table-recipes/actions/runs/38920660514) succeeded in 17m5s from the immutable release tag. Analysis, all 228 Flutter tests, five configuration checks, native compilation, archive and strict app/extension signature checks passed. Xcode reported `ARCHIVE SUCCEEDED` at 15:15:55 UTC and `Upload succeeded` / `EXPORT SUCCEEDED` at 15:19:34 UTC. Apple received 1.5.0/build 16 with delivery ID `5b29ef8f-b05d-4ec0-b28b-b629a8e8d15e`. Apple processing and internal access are checked separately below. The menu-version commit `5e2643c`, created during the builds, was also pushed at the user's request but is outside immutable `v1.5.0` and its packages.

The built-in browser confirmed Apple finished processing: build 16 has status `Ready to Submit`, no Missing Compliance warning, and the existing Family testers internal group with two testers. The embedded exempt-encryption declaration required no manual questionnaire. No new testers, France distribution, external beta review or public App Store submission were configured. No unsigned desktop IPA was produced; TestFlight is the iOS delivery destination. Device acceptance remains user-managed.

## 1.4.0 — reviewed recipe variations

Version `1.4.0+15`, tagged `v1.4.0`, adds reviewed recipe adaptations, family browsing and variation navigation, temporary change explanations, approved parent-photo reuse, clickable source links, recipe-title layout and cooking-temperature fixes. It includes the Android wrapper security update and the exempt-encryption declaration. Supporting backend variation work is recorded separately in the server repository. The user separately approved one signed `xcode-27` build and TestFlight upload for build 15. Web is explicitly deployed and Android delivered to `G:\My Drive\recipe app`; iOS is delivered through TestFlight, excluding France. Release validation follows below after each platform completes.

Local release validation on 2026-10-15: Flutter analysis passed, all 195 Flutter tests passed, and all five iOS configuration checks passed. The full suite initially exposed a source-link integration test inspecting offscreen inline children; it now scrolls the complete source paragraph into view before checking both link destinations. The focused 41 source-link checks and full suite passed afterward. Latest functional backend deployment run `38741522409` succeeded from `bcb7800`; subsequent backend HEAD `ee83c7d` records live validation without runtime changes.

Android release compilation succeeded; metadata confirms 1.4.0/build 15. The APK in `G:\My Drive\recipe app\CoffeyTableRecipes-1.4.0-build15.apk` matches the source SHA-256 `ab871ec84c17a3fab876bc05517d4b74fd7e97b9928e8863680bedbe72fa3cea`. The obsolete numbered 1.3.1/build 14 APK was removed afterward, retaining unrelated files. Web deployment [38749862363](https://github.com/agawlbb/coffey-table-recipes/actions/runs/38749862363) passed analysis/tests, compilation, metadata and hosted asset verification. Public version metadata confirms release source `b896cb53efe674c8dd253f0d7aedeb634cb50d81`, version 1.4.0/build 15. The authenticated recipe collection loaded after a session reload, and backend health passed. The Chicken list loaded after a connection retry; the released full-width title and Variations menu were visually verified on Smoked Jerk Chicken Thighs, with both family members and the current selection visible. No recipe was edited or saved.

Signed iOS run [38749867442](https://github.com/agawlbb/coffey-table-recipes/actions/runs/38749867442) succeeded from the same immutable tag, passing analysis, all 195 Flutter tests, five configuration checks, native compilation, archive and app/extension signature checks. Xcode reported `ARCHIVE SUCCEEDED` at 14:30:32 UTC, then `Upload succeeded` and `EXPORT SUCCEEDED` at 14:34:25 UTC. App Store Connect processed version 1.4.0/build 15 (delivery ID `68aa0f25-b65c-479c-ac11-ae3dec7f9c36`) and shows `Ready to Submit` without a missing-compliance warning. Build details confirm the existing Family testers internal group with two testers. The embedded exempt-encryption declaration required no manual questionnaire. No new testers, France distribution or public App Store/external beta submission were configured. No unsigned desktop IPA or additional macOS run was produced. Physical-device acceptance remains user-managed. Later concurrent image-prefetch edits are outside immutable `v1.4.0`.

## 1.3.1 — category selection and imported-photo defaults

Version `1.3.1+14`, tagged `v1.3.1`, separates parent/child category controls, sorts category selectors, and defaults imported photos to selected while preserving review. Build 14 follows the separately accepted TestFlight 1.3.0 build 13. Web and Android are rebuilt and the hosted app is explicitly published. The user revised the iOS delivery request to a signed build uploaded to TestFlight and separately approved one signed macOS build/upload on the public repository's standard `xcode-27` runner. No unsigned or simulator workflow is requested. App Store Connect processing and tester availability are verified separately after upload.

Verified on 2026-10-13: Flutter analysis passed and all 124 Flutter tests passed. Android release compilation succeeded; APK metadata confirms 1.3.1/build 14 and the destination copy SHA-256 matches `4a6e648c12f98d1bd0be71f2083ca863aad44627081b6b2bad6afa330d65b489` in `G:\My Drive\recipe app`. The obsolete numbered 1.3.0/build 12 APK was removed after verification; unrelated files were retained. Web deployment [38485427067](https://github.com/agawlbb/coffey-table-recipes/actions/runs/38485427067) passed tests, source metadata and asset verification. Public metadata confirms 1.3.1/build 14 from immutable release commit `62055747acf64dec8e513e1ff96d5c5223f3ea3d`. The built-in browser loaded the authenticated recipe collection after a reload resolved an initial household connection error; backend health passed.

Signed iOS run [38485430242](https://github.com/agawlbb/coffey-table-recipes/actions/runs/38485430242) succeeded in 13m23s, including analysis, all 124 Flutter tests, five iOS configuration checks, native archive and strict app/extension signature checks. Xcode reported `Upload succeeded` and `EXPORT SUCCEEDED` at 23:51:29 UTC. App Store Connect received version 1.3.1/build 14, delivery ID `bed37ac6-2987-47c3-b3b3-86322bda6b94`, and finished processing. The user completed the encryption declaration directly in Chrome. The built-in browser then confirmed the compliance warning cleared, build 14 has status `Ready to Submit`, and the existing Family testers internal group is assigned with two invites. No external beta review submission occurred. No App Store release was submitted, no extra macOS run was triggered, and no unsigned desktop IPA was produced for this signed-delivery request. Device acceptance remains pending.

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
