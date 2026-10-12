# Receiving recipe shares

## iOS share sheet with free Apple signing

The share extension imports directly into the hosted table, within the share sheet.
It does not use App Groups, a shared keychain, or an unsupported containing-app
launch. Runner and ShareExtension both have empty entitlement files. The extension
still must be embedded and signed with its own valid provisioning profile; the
signing/install tool must retain extensions. Showing the app in the share sheet
alone does not prove that its signed extension can launch.

Select Coffey Table Recipes, sign in with your app email/password, choose your
table, and tap Prepare recipe. Answer clarification questions when asked, review
and edit the draft, then tap Save recipe. Multiple attachments are reviewed and
saved separately. Done closes the share sheet; open the main app to see the saved
recipes. The main app is not launched automatically.
Returning to the iOS app refreshes the recipe browser while retaining the search
and category scope, so a recipe saved by the extension appears in the collection.

Sign-in belongs to this share session and is separate from the main app. Passwords
and Firebase tokens are not persisted or passed to the main app. Google-only
accounts need to establish an email password using Forgot password in the app
before using this importer. A verified account and an existing table are required,
just as with the main app's hosted API. Internet access is required. Cancelling,
skipping and analysis do not save a recipe. Cancelling an already submitted Save
cannot undo a server commit. If its response is lost, another Save is disabled;
check the table in the main app before sharing again to avoid duplicate recipes.

The extension ships a small local HTML/JavaScript review interface in a
nonpersistent WKWebView. External navigation and web network access are blocked.
A main-frame-only Swift bridge permits reading the share, signing in, analyzing
and explicitly saving, using fixed Firebase and coffeybean.com endpoints. Input
and recipe content are rendered as text, not executable HTML. The editor preserves
structured quantities, categories, steps and timer/temperature actions. Suggested
food photos are not fetched or attached in this lightweight extension; photos can
be added in the main app after saving.

PDF, image, UTF-8 text files, recipe text and HTTPS links are accepted. Files are
copied while the source provider's temporary URL is valid. Each file is limited
to 5 MB, with at most 10 files and 10 MB total per share. HEIC/HEIF images are
converted to JPEG. Captions alongside files do not become additional recipes.
Recipe text and UTF-8 text file content are limited to 60,000 bytes by the API.
The extension deletes temporary copies after loading and releases attachment
bytes as items are saved or discarded. Unsaved input remains only for the current
share session; closing or terminating the extension discards it.

Run `tool/configure-ios.py` with the ignored Firebase build configuration before
building iOS. It also generates ignored
`ios/ShareExtension/ShareUI/FirebaseConfig.json` using `FIREBASE_IOS_API_KEY`,
or `FIREBASE_SHARE_API_KEY` when provided. If the Firebase key has an iOS bundle
restriction, allow the *signed extension's* bundle ID or supply an appropriate
extension key. The native Firebase request includes X-Ios-Bundle-Identifier.
The release workflow runs this configuration step before Xcode bundles ShareUI.
The bundle uses the custom `ShareUI` directory; `Resources` is reserved by iOS
bundle loading and must not be copied as a custom top-level folder.
No backend source or database change is needed.

## Direct file opening and Android

Runner also registers PDF, image and plain-text document opening in copy mode.
Open in/Copy to Coffey Table Recipes, where offered by the source app, launches
Runner directly. SceneDelegate captures cold-start and running-app file URLs in
Runner's own Application Support inbox, bounded to 5 MB, converts HEIC/HEIF images,
and notifies Dart after staging. Dart copies bytes before acknowledging and deleting
staging files. Non-file URLs retain Flutter's normal handler and Google sign-in.
Ordinary iOS launches bypass the legacy share plugin; errors are notifications
rather than empty Add recipe routes. The native inbox now serves document opening
only, with no App Group lookup.

Android registers SEND and SEND_MULTIPLE for document, image and text MIME types.
MainActivity uses singleTask so another share reaches the running app. The
better_share_handler 1.1.0 plugin stages attachments without broad storage
permissions. Shared items wait for sign-in and table selection, then automatically
attempt analysis. Multiple attachments are imported separately; failed input stays
available for retry. Cancelling and analysis do not save recipes.

## Validation

Local checks on 2026-10-11 cover the extension import state machine, configuration
and resource packaging declarations. Cases include explicit-save-only behavior,
selected-table delivery, clarification identity, failed analysis/save retry,
cancel/skip, double taps, sequential attachments, and a lost save response.
The built-in browser checks use a local mock native bridge with sample data;
they do not authenticate a real account, invoke AI or create hosted recipes.
All eight extension-flow tests, five iOS configuration checks, and all 110 Flutter
tests passed, including share imports and refresh after iOS resume. The browser
verified sign-in, table selection,
editable ingredient/instruction review, and explicit-save completion.
Flutter analysis is clean, and the review layout was inspected at a 390-pixel
phone viewport. The generated Firebase share configuration is excluded from Git.

Unsigned iOS 1.1.1/build 10 was built on 2026-10-12 in workflow 38233730579 from
`cd75d29`. Native Xcode compilation passed. Both target versions and the packaged
ShareUI assets and generated sign-in configuration were verified, and the IPA
was copied to the desktop with a matching hash. Signing and physical-device testing
of the redesigned extension remain required. The prior build 9 IPA contains the
old App Group extension; install build 10 to test the redesign.

### Automated share-sheet launch checks

`tool/test-ios-share-simulator.sh` installs the actual Flutter simulator app with
its embedded extension, then builds a separate test-only sender and XCTest UI
suite. The sender invokes Apple's share sheet with a generated PDF or recipe
text. Tests select Coffey Table Recipes, wait for the native attachment read and
web bridge to display sign-in, type into Email, and cancel back to the sender.
They never sign in, call the import service, or save a recipe.

Run the manual `ios-demo.yml` workflow with `simulator_only: true` to test Release
extension compilation on iOS 26 and 27. A third job installs the SDK 26 build on
iOS 27 to check compatibility with the SDK used for device build 10. The workflow
preserves screenshots, XCTest results, extension launch logs and crash reports.
On 2026-10-12, [workflow 38238645998](https://github.com/agawlbb/coffey_table_recipes/actions/runs/38238645998)
from `d30ae96` passed both PDF and text launch/typing/cancel tests in all three
configurations: Xcode 26.3/iOS 26, Xcode 27/iOS 27.0, and the SDK 26.3 app on
iOS 27.0. Screenshot artifacts were downloaded and verified against GitHub's
SHA-256 digests. Eight extension-flow and five configuration tests also passed
locally. This validates the launch path without a provisioning profile.
The test sender is not shipped in the IPA. Its UIScene lifecycle and generated
launch screen avoid legacy presentation and launch failures on newer simulators;
file activities may be accessibility Cells while text activities are Buttons.

Simulator success cannot validate free-account provisioning, Sideloadly's
re-signing, or the exact iOS 27.0.1 physical-device runtime. The user's build 10
installation fails to open from Files after signing with Sideloadly 0.70.1.
Physical-device reports retrieved on 2026-10-12 show builds 8, 9 and 10 terminated
with `CODESIGNING`, code 2, `Invalid Page`. A fresh PDF share at 07:10 EDT on iOS
27.0.1 reproduced it. The live kernel log reports the extension "has entitlements
but is not a main binary". AMFI logs show the extension's application-identifier
uses Runner's signed identity rather than its own extension identity; the profile
is accepted. This identifies malformed extension signing metadata before the
importer runs. It does not prove that merely upgrading the account repairs
Sideloadly's output. Use native Apple signing for the next device validation,
with distinct extension entitlements and proper executable signature flags.
Raw device logs, identities and crash reports are retained only in ignored build
storage. No credentials or device identifiers belong in Git.

Signed-device checks:
1. Sign Runner and the embedded extension using a free Apple account, retaining
   the extension in the installation. Select it from Files/Photos/Safari and
   confirm that the sign-in screen appears.
2. Sign in, choose a table, import a PDF, HEIC photo, text file and website link,
   review and save. Open the app and verify the recipes are present.
3. Share multiple files, saving one and discarding another. Confirm exactly the
   selected recipes were saved.
4. Cancel before Save, reject an oversized/unreadable input, and retry an analysis
   failure. Confirm no recipe was created by these actions.
5. Test a lost Save response and confirm Save cannot be submitted twice.
6. Verify direct file opening, ordinary app startup and Google sign-in in Runner.

References: [Apple extension architecture](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html),
[Apple provisioning capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-ios/).
The extension's password sign-in uses the documented
[Firebase Auth REST endpoint](https://firebase.google.com/docs/reference/rest/auth#section-sign-in-email-password).
