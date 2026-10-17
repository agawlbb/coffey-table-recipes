# Recipe editing

On opening import review or editing, Ingredients and Steps & actions show their
lists. Ingredient details stay closed until the user taps a row or its pencil;
a focused editor puts Amount, Unit, Ingredient, Preparation and Group together.
Done applies those fields together; Cancel discards only that focused edit.
Natural fractions (including mixed and Unicode fractions) update exact scaling
quantities and the displayed ingredient line together. Decimal and fractional
representations are mutually exclusive. Free-form amounts such as “to taste” and
compound measures remain text without invented scaling quantities.

Ingredient groups appear as headings with counts, Rename and Add ingredient
controls. Ungrouped ingredients are shown separately when groups exist. A row's
Move to group menu moves it directly, and also offers reorder/remove controls.
There is one Add group button. Removing a group preserves its ingredients.
Steps show their full instructions and timer/temperature badges. Tapping a step's
pencil or badge opens instructions and all of its actions in one focused editor.
Action fields are visible together, with local reorder/remove controls.

Photos (including previews) and Notes & source are open by default. Categories
and tags remain at the bottom of Recipe details with parent/category controls
visible. The Category dropdown shows only child names, alphabetically, and an
Add new category option; typing or clearing a new name preserves its parent.
A small cover preview near the recipe name links directly to Photos.

Section shortcuts remain pinned below the app bar while scrolling. Prep, Cook
and Total show compact durations that open hours/minutes editors; timers also
have seconds. API storage remains minutes for metadata and seconds for actions.
New imported recipes show “Draft—not saved yet” and the final action is Save
recipe. Save validates ingredients, steps and actions even when their detail
editors have never been opened, then opens the item needing attention.

Import offers a consistent two-by-two grid of Text, Website, File and Camera.
Text can be marked as a description of how the user makes a dish. The character
counter appears only near the limit. The flow is source, clarification questions
only if needed, review, then Save recipe. Edit source returns to the retained
source input and draft; Return to review makes no additional AI request.
Preparing again explicitly replaces the current review with the updated source.
Cancelling review exits to the screen where the import started.

Verified on 2026-10-16: the final 48 editor/import/quantity/variation checks
passed and Flutter analysis was clean. The broader regression run passed the
remaining checks; its outdated live-title expectation was corrected and verified
in the final variation suite. Image/source-photo regression checks also passed.
Local web and Android debug builds succeeded. On the Pixel 8 emulator, Breakfast
Ring showed Dough (4) and Sauce (3), pinned navigation, cover preview, and a
focused ingredient editor with quantity, unit, preparation and group together.
No hosted recipe data was changed during these UI checks.

Verified on 2026-10-12: all 32 editor/import/image/source-photo tests passed,
Flutter analysis was clean, and local web and Android debug builds succeeded.
The rebuilt Pixel 8 emulator was checked for import choices, single-row
shortcuts, numeric/time fields, visible categorization, category picker cancel,
flat ingredient rows, complete step instructions, timer badges and photo previews.

2026-10-13 correction: parent and category use separate dropdowns, with only
child names shown in Category. Its Add new category option keeps both selectors
available. Clearing the new name preserves the parent. Prepared source pictures
are included by default. All 32 editor/import/image/source-photo tests passed,
including clearing a new category name, returning to an existing category and
saving an automatically selected source picture. Flutter analysis was clean.

Pictures in import review and the recipe editor have an **Edit picture** tool.
Image uploads and camera pictures also have this tool on the initial import
screen; extraction uses the edited PNG. PDF documents are not modified.
Drag crop corners, rotate in either direction, flip horizontally, optionally
resize, or reset. Apply updates only the recipe draft; Cancel preserves the
previous picture. Normal recipe Save persists the edited bytes, preserving the
photo ID, credit, caption and cover choice. Imported pictures are selected automatically and the first becomes the cover
when no cover exists; users can edit or remove them before saving. Existing pictures load through the
photo cache and require connectivity if not cached. Edits run locally on web,
Android and iOS with Flutter image APIs, with no AI or image-service request.
The existing 5 MB save limit applies; resize/crop smaller if needed.
Validation includes pixel checks for crop/rotation/flip, resize dimensions,
cancel/apply and metadata preservation, and edited PNG delivery to import.
Recipe editor, import, shared-file and source-photo regressions pass; Flutter
analysis is clean. Web/Android test builds compile. iOS uses the same Dart tool,
but native iOS compilation and device validation require macOS/Xcode.

Open a recipe and select the pencil beside its name. The editor uses the app's
existing Material theme, centered content, rounded cards, and expandable sections.
Save commits the entire draft; Cancel and back navigation prompt before discarding
unsaved changes. Errors keep the draft available for correction or retry.

The editor now shows the recipe name and shortcuts to each section. A shortcut
opens its section and scrolls it into view. Servings/yield and cooking times share
rows when space permits; phone layouts stack fields as needed. Language and
measurement settings are under Language & measurements.

Cooking action durations use Hours, Minutes and Seconds fields. Prep, cook and
total times use compact buttons opening Hours and Minutes fields, matching the
database's whole-minute precision. Durations display in hours, minutes and seconds across
recipe views, collapsed action previews and cooking mode; running timers switch
to `h:mm:ss` at one hour. Input validation checks component ranges and positive
timer durations. Storage remains seconds for actions and minutes for metadata.
Validation covers duration round trips, invalid component ranges, editor save
payloads and visible errors, recipe browsing and cooking timer regressions.
Flutter analysis passes.

Ingredient rows preview their displayed quantities and preparation; step rows
preview instructions. Open a focused editor using the row or pencil. Amount,
unit, name and preparation are synchronized rather than independently editable
representations. Reorder/remove controls use row menus or the focused action
editor; group selection is directly available from each ingredient row.

A persistent footer shows unsaved changes and save errors. Validation opens the
sections and rows containing the first invalid field, then scrolls to it. All edits
remain in the same draft when moving between sections.

Editable content includes the name, description, servings/yield, cooking times,
language, measurement system, ingredient groups and all ingredient fields,
ordered steps and their ordered cooking actions, photos/captions/credits/cover,
browse categories and tags, notes and source attribution, original-recipe links,
pairings/notes, and nutrition. Recipe IDs, revision/audit fields, import keys,
extracted import source text, favorites, and cooking history remain managed by
their respective systems.

The ingredient line is the text displayed while viewing and cooking. The Amount
field derives exact decimal/fraction/range quantities; fractions require a
positive denominator and cannot be combined with a decimal quantity. Removing a group ungroups its ingredients.
Removing a step removes its actions. Reordering keeps IDs and associations.
Changing an action type resets values specific to its previous type.

Upload image uses the device photo picker. Use camera captures a device photo;
on the web it requests camera capture through the browser's file picker, with
behavior depending on browser/device support. Native iOS photo/camera usage
descriptions are configured. Android lost-picker results can be recovered when
the editor is reopened. Actual device permission/capture behavior requires a
physical-device check. Photos are staged in the draft until Save and can be
reordered, removed, credited, captioned, and selected as the single cover.
The server accepts JPEG, PNG, and WebP, up to 5 MB/24 megapixels each, 20 photos,
and 20 MB of new image data per save. New media is excluded from Git.

Saving needs a connection. The server checks the loaded revision and rejects
conflicting edits with an explanatory message. A successful response updates the
view immediately and the mobile offline cache, then refreshes household downloads.
Nutrition remains stale unless the user confirms that its values apply to the
edited recipe.

Validation on 2026-10-11: all 77 Flutter tests passed, including six editor/cache
tests; app-themed phone/desktop visual checks passed; web and Android debug builds
passed. Backend verification passed 28 edit checks and 55 existing schema checks
using disposable local databases. Deployment status is recorded in the backend
repository's docs/recipe-editing.md. Hosted Flutter publication requires the
separate explicit release workflow.

Editor refresh validation on 2026-10-11: all 79 Flutter tests passed and
`flutter analyze --no-pub` reported no issues. Coverage includes section shortcuts,
draft preservation, previews, validation visibility within the logical viewport,
reordering/removal, photo drafts, save errors and a 360-pixel phone layout.
The web build was published to local XAMPP using `tool/publish-local-web.ps1`.
Integrated-browser visual checks passed at 360 and 1280 pixels wide using the
hosted backend. This publication updates the local app only.

2026-10-17: Ingredient rows now expose a Delete ingredient icon beside Edit; deletion changes the draft and takes effect when Save recipe succeeds. Group headings remain bold and grouped rows are slightly indented. Recipe details and the cooking-mode ingredient sheet use bold headings and a 16px member indent; ungrouped ingredients retain their alignment. Regression coverage verifies the saved deletion payload at 360px and heading weight/member positions in both display contexts. No app builds were created for this change.

2026-10-17: Touch and hold an ingredient row, then drag it to reorder within its group (or within the ungrouped list). The existing Move to group menu changes group membership. Dragging updates the draft list order, which is persisted on Save recipe; ingredient identities and group assignments are retained. A touch-gesture regression moves the first ingredient to the end and checks the save payload and unaffected ungrouped ingredient. No app build was created.
