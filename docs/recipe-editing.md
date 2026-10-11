# Recipe editing

Open a recipe and select the pencil beside its name. The editor uses the app's
existing Material theme, centered content, rounded cards, and expandable sections.
Save commits the entire draft; Cancel and back navigation prompt before discarding
unsaved changes. Errors keep the draft available for correction or retry.

The editor now shows the recipe name and shortcuts to each section. A shortcut
opens its section and scrolls it into view. Servings/yield and cooking times share
rows when space permits; phone layouts stack fields as needed. Language and
measurement settings are under Language & measurements.

Ingredient rows preview their displayed quantities and preparation; step rows
preview instructions. Open a row using its heading or expand arrow to edit it.
Reorder and remove controls appear at the bottom of the expanded row. Grouping,
scaling, and exact ingredient quantities have their own expandable settings.
The displayed ingredient line is edited independently from search/scaling fields.

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

The ingredient line is the text displayed while viewing and cooking. Exact
decimal/fraction/range quantities are available beneath Exact quantities;
fractions require both a numerator and positive denominator and cannot be
combined with a decimal quantity. Removing a group ungroups its ingredients.
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
