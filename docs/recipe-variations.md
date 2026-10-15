# Recipe variations

Each editable recipe detail has **Request variation**. Describe the changes,
answer any AI follow-up questions, then use the existing import review editor.
Only **Save** creates the new recipe. The chosen parent is fixed during review,
and the parent recipe is never edited by this flow. Saved variations open
immediately, display a Variation badge, and link to their parent, siblings, and
children in Recipe family. List cards also show the Variation badge.

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
