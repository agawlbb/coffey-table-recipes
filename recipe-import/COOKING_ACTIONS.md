# Imported recipe cooking actions

Completed October 9, 2026 in hosted `hosting_account_recipes`, household 2, recipe IDs 9–21.
All 199 cleaned instructions were reviewed. Added 49 records to the existing
`recipe_step_actions` table: 23 timers, 10 timed rests, 11 appliance temperature
targets, one custard internal temperature target, and four reminders. No database
structure, backend API, instruction text, source text, ingredients or photos changed.
Each affected recipe revision increased once so clients can recognize the change.

Examples: muffins have a 350°F oven target and a 15-minute check timer; queso has
a 225°F pellet-grill target, a two-hour timer and a separate 30-minute stir timer;
mint ice cream has a one-hour infusion rest and a 170°F custard target. The mojito
has syrup-simmer and mint-steeping timers.

Review conventions:

- A duration range starts a timer at the earliest check time. The label retains
  the complete range and any stated doneness condition. Approximate times retain
  “about”; minimum chilling times retain “at least” and the required cold condition.
- “Overnight” remains a reminder without an invented numerical duration. Storage
  limits and optional day-ahead directions do not become countdown timers.
- The queso stirring timer is manually restarted every 30 minutes. The current
  app does not implement automatic repeat timers.
- Appliance targets are displayed instructions. They do not control appliances.
- Bun baking, orange-chicken frying oil, queso grilling and crab baking sources
  omit the temperature unit. Their 350/350/225/350 targets were interpreted as
  Fahrenheit from the US recipe context and conventional cooking temperatures.
  Explicit Celsius alternatives remain in the original step text or action label.
- Timers are attached to their exact cooking or rest step, not a preparation step.
  No new internal-temperature recommendations were introduced beyond the source.

`HostedActions::sql($recipes, $household, $user)` produces a data-only transaction.
Each snapshot supplies an ID, expected revision, ordered instruction array and
actions keyed by one-based step position. It locks the recipe and checks membership,
revision, step count and the complete ordered instruction digest before inserting.
A recipe with existing actions is skipped so user-created actions are preserved.
Existing step IDs are resolved from the matching position and instruction.
Re-running the same batch skips already updated recipes and adds no duplicates.

Validation:

- `C:/xampp/php/php.exe recipe-import/test-actions.php`: 22 portable fixture checks
  in a disposable local database, including stale instructions, existing actions,
  disabled users, invalid durations/units, step association and repeated execution.
- `C:/xampp/php/php.exe recipe-import/test-actions.php recipe-import/generated/actions-plan.json`:
  360 checks against the complete private batch, with exact action fields verified.
- Hosted verification compared ordered digests of every action field, including
  step position and action position, against the plan. All thirteen matched, every
  instruction digest remained unchanged, and all recipe revisions advanced once.

Private plans, audit snapshots, generated SQL and screenshots remain ignored under
`generated/`. The ordinary local recipe database was not changed.
