# Recipe variations

Opening a recipe prefetches all photos for that recipe, every member of its
variation family, and recipes explicitly linked under **Serve alongside**.
Images use the existing mobile disk cache (90 days, up to 100 objects) or the
web image cache. Prefetching runs in the background, deduplicates recipes and
URLs within the batch, tolerates unavailable recipes/images, and stops queued
work when the detail view is disposed or the app goes offline. It does not
recursively follow links from the related recipes or match ordinary category tags.

Each editable recipe detail has **Request variation**. Describe the changes,
answer any AI follow-up questions, then use the existing import review editor.
Only **Save** creates the new recipe. The chosen parent is fixed during review,
and the parent recipe is never edited by this flow. Saved variations open
immediately and display a Variation badge. The recipe browser shows one entry per
variation family. Next to the recipe title, a compact **Variations** menu lets the user
switch to any live member of the family, including nested variations. Recipes
without other family members show no dropdown.

Cancel or Back in the prompt asks before discarding entered work. Cancel or Back
in review uses the existing editor's discard confirmation and returns to the
originating recipe. Cancelling while generation runs ignores its late response.
If generation finishes behind the discard confirmation, Keep working leaves a
Review variation button available. Network and service errors preserve inputs;
retrying an unchanged request retains its identity. Editing the request after a
failed attempt creates a fresh identity. Follow-up retries do not duplicate
answers. A failed Save keeps the editor open and retains the import key.

## API contract

POST `/households/{household}/recipes/{parent}/variation` with:

- `changes`: requested changes, at most 4,000 characters
- `request_id`: 32 lowercase hexadecimal characters; fresh per new attempt,
  stable for unchanged retries and clarification rounds
- `answers`: cumulative `{question, answer}` pairs when present; answers at
  most 2,000 characters each

The response is the import-compatible `{recipe, questions, change_description}` envelope. Generation
uses the same 110-second client timeout as import, including after token refresh.
The backend owns the parent binding, stable `import_key`, and `ai_variation`
source type. The editor preserves that machine source type rather than replacing
it with its display label. The approval flow removes any response `id` before
editing to ensure Save uses POST `/households/{household}/recipes`.

Generation responses bypass offline save-cache updates and background collection
sync. The offline cache independently accepts only true creation/update/delete/
restore routes with a saved ID. After Save, the approved new recipe is cached
under its own ID; a preview cannot replace the cached original.

`related` rows may specify `relationship` as `parent`, `sibling`, or `child`.
The UI falls back to parent IDs for older responses. `is_variation` or a non-null
`parent_recipe_id` supplies the explicit badge even if editable tags change.

## Grouped browsing

Browser requests include `families=1`. The backend filters/searches all members,
then returns one representative per matching family before pagination. A search
for a variation's title or ingredients therefore finds its family without adding
a separate variation card. Category counts count each family once. The original
is the representative while it is live; if deleted, one remaining member keeps
the family reachable.

Detail responses include `variation_family` (all live connected family members)
and `family_representative_id`. Deleted links may connect live descendants, but
deleted recipes and other households never appear in the dropdown. The older
`related` response remains a fallback for older servers. The old bottom-of-page
family list is replaced by the menu.

Offline inventory sync still downloads every saved variation. Only browser
results are grouped, including offline search; dropdown navigation still opens
the cached variation details. Save refreshes family lists in cached relatives;
deletion removes the deleted entry from those lists.

The backend enables generation for all authenticated household members by default.
An explicitly disabled or restricted backend policy still displays its error and
leaves the user's input available.

## Complete adaptations and review explanation

Generation reviews all affected recipe details, including quantities, ingredient
preparation, cooking instructions, equipment, temperatures, timers, prep/cook/total
times, resting, yield, notes, categories, description and title. A substitution
must carry through to the method and timing; a title that no longer describes the
dish must change. Revised step instructions supply the matching timer and
temperature actions. Unaffected details remain intact.

The review editor shows **How the recipe changed** above the recipe fields.
`change_description` explains the actual modifications and their cooking effects.
It is held separately from the recipe in widget state and is never submitted in
the Save payload, appended to notes or description, or written to the database.
The server's private retry cache retains the response, including the explanation,
for consistent generation retries. Older responses without an explanation remain
reviewable without an empty information card.

## Validation

Family browser update (October 15, 2026): all 194 Flutter tests pass and analysis
reports no issues. Backend validation passed 569 PHP fixture checks and 65 Python
deployment checks. Backend `a3b1a33` deployed successfully with matching source
hashes and hosted receipt; the rebuilt localhost JavaScript matches the build.
Live built-in-browser verification found one jerk-chicken search entry, opened
the title dropdown on Smoked Jerk Chicken Thighs, and switched successfully to
the saved Smoked Jerk Boneless Chicken Thighs. No recipe data was modified by this
verification. The dropdown remains available on the selected variation.

Local integration on October 15, 2026: merged the feature branch into `main` and
deleted the local feature branch. Flutter analysis reports no issues and all 194
tests pass, including 45 variation/offline tests. Coverage verifies explanation
display through clarification rounds and exclusion from Save payloads. The web
build succeeded and was republished to localhost. Backend commit `138efbf` passed
the Linux deployment workflow; the hosted version receipt matches and API health
is OK. Backend validation includes 550 PHP fixture checks, including database
exclusion of the review explanation. Provider responses were mocked; live AI
cooking quality still requires review when generating a variation.

Automated coverage is written in `test/recipe_variation_test.dart` and
`test/offline_recipes_test.dart`. Run:

```sh
flutter analyze
flutter test
```

The October 15, 2026 cloud implementation was parsed/formatted with Dart 3.13.5.
Flutter analyzer and widget tests were not executed in this cloud verification
pass; the Flutter dependency setup was not completed. No mobile build, production
API call, or deployment was performed.

Manual review checklist after tooling and backend configuration are available:

1. Request a variation, answer multiple clarification rounds, and confirm the
   original is unchanged before and after approving Save.
2. Retry failed generation and failed Save; confirm only one approved recipe is
   created. Change the request after a failed generation and confirm the new
   prompt is used.
3. Cancel during generation, cancel/back from review, and repeat taps; verify no
   abandoned response opens another page or creates a recipe.
4. Let generation finish while the discard dialog is open. Choose Keep working
   and review the draft.
5. Confirm parent/sibling/child navigation, explicit variation labels, source
   type preservation, and the fixed parent during approval.
6. Go offline after previewing and after saving. Verify the original remains
   intact and only the approved variation is available offline.
7. Verify disabled/access-denied errors, connection recovery, narrow-screen
   layout, and that the existing standard import/edit flows still work.

## Compact variation selector

The title uses the full recipe content width. The Variations label and small chevron sit on the left of the edit/share/delete row below it. Family
choices appear only when tapped; the current recipe has a checkmark. The menu
keeps long titles separate from the controls on narrow screens and is omitted when no other
family member exists. The large outlined selector beneath the title is removed.

Validation: Flutter analysis is clean; all 22 variation/browser tests pass, including the inline menu at 400px width, initially hidden choices, family navigation and omission on recipes without alternatives.

Rebuilt and published localhost; JavaScript hashes match. Live built-in-browser verification on Smoked Jerk Chicken Thighs confirmed the inline label, hidden choices until tapping, the checked current recipe, and both family choices.

## Parent cover reuse

The backend visually reviews the parent's cover during generation. When the AI
judges it still representative of the variation, the review draft includes a new
photo containing those pixels and the original caption/attribution. The existing
Photos editor previews it and Save creates an independent photo record and file.
Unsuitable, uncertain or unreadable covers are omitted. The temporary variation
explanation describes that decision; the parent is never modified. No extra
image-generation request is made, and the decision is not a saved recipe field.

The 17 variation widget tests pass, including previewing and saving an approved
cover with a fresh photo identity and without submitting parent_cover_review.
Backend fixtures validate visual input, suitability decisions, attribution,
image-change cache invalidation and independent persistence.

Live validation on backend 8f35ae3: the mild jerk-chicken variation explanation confirmed reuse of the suitable parent image, and Photos displayed the matching image as Photo 1 / Cover. The draft was left unsaved. Flutter analysis is clean.

## Variation titles

New variations use the main family title followed by ` - ` and a short variation
phrase, for example `Smoked Jerk Chicken Thighs - boneless thighs`. The backend
assembles this title from its trusted main title and the AI's variation label.
Variations of variations keep the same main title rather than stacking full
parent titles. Existing saved recipes are not automatically renamed.

Live verification against backend bcb7800 returned exactly Smoked Jerk Chicken Thighs - boneless thighs for the request uses boneless thighs. The test draft was not saved. Backend validation passed all 599 PHP fixture checks.

Action-row layout: the title uses the full content width. The compact Variations control sits below it on the left, with edit, share and delete on the right. Flutter analysis is clean and all 23 variation/browser tests pass, including title width and action alignment at 400px. The web build was published to localhost, its JavaScript hash matches the build, and the recipe layout was visually verified. The Android debug build was installed and launched on the Pixel 8 API 36 emulator; MainActivity was confirmed in the foreground.
