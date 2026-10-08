# Food bookmark collection

Collected October 8, 2026 from the Chrome default profile's Food bookmark folder. No database mutations were performed.

- `bookmarks.json`: all 14 original bookmark titles and URLs.
- `recipes.json`: source Recipe JSON-LD, resolved source URLs, collection timestamps, and per-bookmark fetch status.
- `import-ready.json`: eight recipes with original ingredient wording, flattened cooking steps, structured instructions, attribution, yield, times, and source nutrition when supplied.

Run `collect.ps1` to refresh source extraction, then `prepare.ps1` to regenerate the import bundle. Collection requires network access. Neither script connects to the database.

The import bundle is independent of the pending database schema. Map it to that schema once available; use source URLs to prevent duplicate ingestion. Preserve original wording and units. Numeric quantity parsing, household assignment, and database validation remain ingestion work. Source-provided nutrition is unverified and should retain its provenance. Image URLs are references only; images were not downloaded.

Eight collected recipes: Mint Chip Ice Cream; Hot Fudge Chocolate Pudding Cake; Coffee-Chocolate Layer Cake with Mocha-Mascarpone Frosting; Homemade Hamburger Buns (Bread Machine); Chinese Buffet Crab Casserole; Chinese Orange Chicken; Bran Flax Muffins; Smoked Queso.

Remaining bookmarks are recorded in `recipes.json`: five failed fetches and one page needing manual extraction. Legacy Genius Kitchen and Cafe Delites addresses were updated to their current recipe addresses. Review the collected recipes before treating them as verified cooking data.
