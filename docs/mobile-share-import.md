# Receiving recipe shares

Android registers SEND and SEND_MULTIPLE for PDF, generic document, image and text
MIME types. MainActivity uses singleTask so another share reaches the running app.
The better_share_handler 1.1.0 plugin stages content URI attachments without broad
storage permissions. Text and HTTPS links are accepted as well as files.

On iOS, Runner embeds ShareExtension. Both targets use App Group
`group.com.coffeytable.coffeyTableRecipes`. The extension links the models product
from the pinned plugin's generated Swift package, then hands content to the app
through ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER). Google callback configuration
preserves this URL scheme. Signed device builds require this App Group in both
provisioning profiles. The extension supports images, files, URLs and text.

The inbox handles initial and running-app delivery. File bytes are copied into
app-owned memory immediately so native staging cleanup cannot invalidate a pending
import. Pending shares survive sign-in and household selection within the running
process. If the process is terminated before import, share again; the in-memory
queue is not durable storage. Multiple attachments are imported separately; a
file caption does not create an extra recipe. Oversized/unreadable files produce
an import error rather than an AI call. Existing 5 MB input and PDF/JPEG/PNG/WebP
server format checks apply. Unsupported files show an actionable error.

Once a household is available, sharing opens Add recipe and attempts analysis.
Text files are read locally before submission. Clarification questions and editor
review precede normal Save. Cancel and failures do not create database records;
failed input remains available to retry. Saving refreshes the recipe collection
and updates the normal mobile offline cache.

Validation on 2026-10-11: incoming-share tests cover initial/running delivery,
staging-file removal, and automatic text/text-file analysis without saving. Import
and editor regressions pass; Android debug APK compiles. iOS plist/configuration
tests verify matching groups, activation rules, and Google/share scheme coexistence;
the Xcode project parses with target dependency and extension embedding intact.
iOS compilation and physical share-sheet testing require macOS/Xcode and devices.

Device checks before release:
1. Signed in, share a PDF from Files and an image from Photos; verify import review.
2. Close the app and share again; verify cold launch and exactly one import.
3. Signed out, share; sign in/select a household and verify the pending import opens.
4. Share multiple files and confirm each is reviewed separately.
5. Cancel or submit an unreadable/oversized file and confirm no recipe is created.
6. Verify Google sign-in remains functional on the signed iOS build.

Plugin setup: https://pub.dev/packages/better_share_handler
