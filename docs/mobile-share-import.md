# Mobile recipe sharing

## iOS with paid Apple developer signing

The share receiver accepts PDFs, images, text and website links from the iPhone
share sheet. It stages files and atomically publishes a manifest in an App Group.
It displays “Ready to import. Open Coffey Table Recipes to review your recipe.”
Tap Done, then open the main app. iOS does not offer a supported automatic launch
of the containing app from a Share extension. No separate account sign-in or web
importer runs in the receiver.

Runner reads both the shared container and its own document-opening inbox on
startup and resume. Dart copies attachment bytes before acknowledging and removing
staging files. Existing sign-in and table selection control import into the main
app, followed by analysis, review and explicit Save. Signing out does not discard
pending input. File captions do not create extra recipes. Each attachment has its
own review. Failed analysis can be retried; Cancel does not save a recipe.

Files are limited to 5 MB each and at most 10 per share. HEIC/HEIF images are
converted to JPEG. Shared text is bounded to 60,000 bytes. Closing after successful
staging preserves pending shares until the main app consumes them. The receiver
does not contact the backend or hold credentials.

## Signing preparation

Use the paid team in Xcode for both targets:

| Target | Bundle ID |
| --- | --- |
| Runner | `com.coffeytable.coffeyTableRecipes` |
| ShareExtension | `com.coffeytable.coffeyTableRecipes.ShareExtension` |

Register `group.com.coffeytable.coffeyTableRecipes` and enable it for both App IDs.
Both committed entitlement files and both Info plists contain this same group.
If an identifier is unavailable in the new account, update it consistently in
Xcode, both Info plists and both entitlements before signing. Update Firebase's
main iOS app registration and Google callback if Runner's bundle ID changes.

On a Mac, install Xcode 27 or newer and Flutter 3.47.7, add the paid account to Xcode Settings,
then open `ios/Runner.xcworkspace`. Select the paid team for Runner and
ShareExtension and leave automatic signing enabled. Xcode must create a separate
provisioning profile for each target with the same App Group membership. Do not
reuse Runner's application-identifier entitlement for the extension.

For a repeatable archive, set `IOS_TEAM_ID` and `IOS_FIREBASE_CONFIG` (the ignored
Firebase JSON path), then run `bash tool/build-ios-signed.sh`. The script builds,
archives with Apple's signing tools, checks both signatures, and exports to
`build/ios/signed`. Its default `debugging` export installs on development devices;
register the phone with the team. Set `IOS_EXPORT_METHOD=release-testing` for
registered-device distribution, or `app-store-connect` to export for TestFlight.
The script does not upload. Certificates, profiles, account credentials and build
outputs stay outside Git. Actual signing needs the new account's team and valid
signing identity; preparation alone is not a signed-device validation.

## Direct file opening and Android

Runner registers PDF, image and plain-text document opening in copy mode. Where
the source offers Open in/Copy to Coffey Table Recipes, the file reaches Runner's
own inbox directly. SceneDelegate handles cold and running app delivery. Normal
URLs retain Flutter and Google sign-in handling. Ordinary launches bypass the
legacy iOS share plugin. Android continues to use its SEND/SEND_MULTIPLE receiver.
The hosted coffeybean.com backend is unchanged.

## Validation and known signing failure

The simulator workflow builds the real embedded receiver in Release, ad-hoc signs
simulator App Group entitlements, selects it from actual PDF/text share sheets,
checks the ready screen and Done, and verifies persisted PDF bytes and text.
Flutter tests cover pending delivery, authentication gating, acknowledgment and
recipe review. Simulator success does not validate paid provisioning on a phone.

On 2026-10-12, source `e2198f5` passed the PDF and text receiver tests and verified
the persisted PDF bytes/text in both SDK 26/iOS 26 and SDK 27/iOS 27 jobs of
[workflow 38242987112](https://github.com/agawlbb/coffey_table_recipes/actions/runs/38242987112).
The additional SDK 26-on-iOS 27 check passed text but failed to display the PDF
receiver. That legacy compiler/runtime combination is not verified. Paid signing
and unsigned device builds now use Xcode 27; the signed-build helper requires
Xcode 27 or newer. Eight main-app sharing tests, five configuration checks, clean
Flutter analysis and signing-script syntax checks passed locally. The actual
paid archive/export cannot be validated until the team and signing identity exist.

On 2026-10-12, physical iOS 27.0.1 reports for builds 8, 9 and 10 signed with
Sideloadly 0.70.1 show `CODESIGNING`, code 2, `Invalid Page`. A fresh tap reproduced
it. The kernel reports that the extension “has entitlements but is not a main
binary”; AMFI logs show Runner's application-identifier in the extension's signing
data. The provisioning profile is accepted. This happens before the importer can
run. Earlier build 10 importer code passed PDF/text launch tests on iOS 26 and
27, including an SDK 26 build on iOS 27, in workflow 38238645998. Those results
belong to the retired separate importer, not this shared-inbox design.

Use Apple-native signing to validate the new design; a paid account by itself
does not establish that Sideloadly's output is corrected. Device logs remain only
in ignored build storage. After signing, verify Files PDF, Photos HEIC, text and
Safari URL delivery, both cold-start and resume; sign-in/table selection; multiple
files; explicit save and cancellation; and Google sign-in in Runner.

References: [Apple App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups),
[Flutter iOS deployment](https://docs.flutter.dev/deployment/ios).
