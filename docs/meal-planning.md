# Household meal planning (version 2 feature branch)

`codex/meal-planning-v2` is owned by the Plan CTR meal planning v2 chat. The
matching backend branch is in the canonical PHP repository. This work does not
change the release version, main branches, release tags or published app.

## Interaction

Open Meal planner from the existing navigation drawer. The scrolling date list
opens with today near the middle; Today returns there. Earlier dates have a
darker background and today has the primary tint. Each date offers Add: Recipe
opens the existing recipe browser in selection mode; Leftovers and Restaurant
outing create matching placeholder tiles. The recipe browser stays beside the
date list on wide screens and supports dragging recipes into the plan.

Hold a tile to drag it to another date. Meal options offer Move to date,
Unscheduled and Remove; tapping the recipe opens its normal detail page.
Recipe-browser long press and the recipe detail page offer Add to meal plan.
These additions go into the household's Unscheduled section, visible only when
it has entries. The recipe action's View plan shortcut returns to the planner.

A recipe newly assigned to a date offers existing frequently paired recipes,
excluding recipes already there. This also applies when scheduling an
unscheduled dish. Moving between dates never offers pairings. Suggested additions
do not recursively offer more suggestions. Placeholders have no ingredients,
recipe history or pairings.

Adding, removing, or moving into/out of a past date asks once before the change:
“Change this past meal? This will update your cooking history.” Cancel does not
write. API enforcement covers stale screens and midnight rollover too.

## Shared state and history

All members use the selected household's plan. The API supplies the household's
today and timezone, initially America/New_York, rather than deriving shared dates
from a traveling member's device timezone. Changing that default for an existing
household is a deliberate data change, not an automatic timezone guess.

Each operation compares the household revision. Conflicting edits refresh the
screen and ask the user to review/retry, without silently replaying the write.
The planner refreshes on return/resume and every 30 seconds while active. Writes
require a connection; no offline mutation queue is introduced.

Dated recipe entries themselves are durable preparation history once their date
is before household today. No confirmation or daily job is needed. Correcting a
past entry corrects that history. Each occurrence keeps the recipe identity,
title and revision snapshot even if the recipe is later purged. The history API
also returns existing recorded cooking events and their deleted-recipe archives;
it does not duplicate those events during reads. Future recommendation features
can consume this API; recommendation screens are outside this implementation.

## Ingredients and shopping

Ingredients opens a date-range picker for today/upcoming meals, then reuses
RecipeShoppingSelector and the same shopping-list write helper as recipe detail.
Each scheduled occurrence contributes once. Explicit amounts with the same
ingredient name, compatible unit spelling, preparation and optional status are
summed. Ambiguous text amounts, ranges and incompatible units remain separate;
no mass/volume or density conversion is guessed. Existing shopping duplicate
warnings and revision-safe additions are preserved. As in the existing recipe
flow, the shopping list receives selected ingredient names; quantities are shown
in the ingredient review. Unscheduled dishes and placeholders are excluded.
Unavailable scheduled recipes stop collection rather than silently omitting
their ingredients. Per-meal serving overrides are not introduced.

## Validation

Flutter analysis and the full 373-test regression suite passed during initial
implementation. Planner tests cover past cancellation/confirmation, placeholders,
dragging with pairing rules, recipe-picker reuse, conflicts and ingredient sums.
The backend adds membership, date/timezone, revision rollback, history rollover,
purge retention and repeated-occurrence ingredient fixtures. See the PHP
repository's docs/meal-planning.md for migration/deployment and hosted results.
