# Hosted instruction cleanup

Completed October 9, 2026 in `hosting_account_recipes`, household 2, imported recipe IDs 9–21.
All thirteen recipes were reviewed for combined operations. The 68 source paragraphs
became 199 ordered instructions. Muffins now have seven steps, stuffing thirteen,
and crab in wine sauce ten. Yield statements were removed from cooking instructions;
the existing yield fields remain. HTML entities in the bun directions were decoded.
Times, temperatures, optional branches, and cooking cautions were retained.
The mojito has an editorial mixing instruction based on its four listed ingredients;
its original source text remains available.

`HostedCleanup::sql($before, $parts, $photos)` generates a data-only transaction for
this destination and importing owner. `$before` contains audit rows in the order
`id,title,yield_text,revision,step_id,position,instruction`; `$parts` maps existing
step IDs to an ordered array of replacement instructions. Each existing ID is kept
for its first replacement; additional instructions receive new IDs. There are no
deletes or schema/API changes. Recipe revision, exact instruction, step count,
membership and attached-action guards prevent applying a stale plan. Recipes with
attached step actions require a reviewed action mapping rather than automatic splitting.
An already applied batch skips on rerun. Photo URLs are idempotent; existing photos
remain, with the new illustration selected as cover.

Private snapshots, curated plans, generated SQL and screenshots are in the ignored
`generated/` folder. Do not commit them. phpMyAdmin renders some repeated ordinary
spaces as nonbreaking spaces: verify exact stored bytes before repairing an audit
snapshot, rather than weakening the instruction guard. This was necessary for the
bun note and two muffin instructions; they were then applied in a second guarded batch.

Validation:

- `C:/xampp/php/php.exe recipe-import/test-cleanup.php` uses portable fixtures in a
  disposable database and checks IDs, source preservation, position collisions,
  reruns, stale instructions, attached actions and disabled users.
- Optional private batch validation:
  `C:/xampp/php/php.exe recipe-import/test-cleanup.php recipe-import/generated/cleanup-before-steps.json recipe-import/generated/cleanup-plan.json`.
- Hosted verification found every recipe's ordered instruction digest exactly
  matched the curated plan, all step positions were contiguous, and no embedded
  yield or escaped quote/degree artifacts remained. Original source hash prefixes
  matched the before audit, and every recipe had exactly one cover.
- Crab and mojito covers are hosted JPEG illustrations, 1254×1254, each checked in
  the built-in browser. Their captions identify them as AI-generated illustrations.

The local recipe database and application API were not modified.
