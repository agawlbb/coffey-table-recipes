# Parent category administration

Open Administration and select **Manage parent categories** to add or rename shared parent categories, or delete an empty parent after confirmation. The screen explains that the catalog applies to every household.

Delete is disabled when the parent has subcategories or direct recipe assignments. The backend independently enforces emptiness across all households, including Recently Deleted. Removing an empty parent cannot remove recipes or subcategories. Errors remain visible and Refresh retrieves current availability.

The feature uses the administrator-only `/admin/parent-categories` backend endpoint. There is no household-menu entry and household ownership does not grant catalog management access.

Validation: Flutter analysis passes with no issues; all 12 category and administration widget tests pass. The suites cover navigation from Administration, add, rename, delete confirmation/cancellation, blank input, disabled nonempty deletion, server rejection, and existing user and household controls.

On 2026-10-15, backend commit `c78f80d257f532d635ae7b73b613754c31776341` deployed successfully through the Ubuntu backend workflow. The hosted receipt matches that commit and the new endpoint returns 401 without authentication. The workflow passed its backend and deployment checks, including the 29 category checks. No live catalog entries were changed for validation. Authenticated hosted interaction remains to be exercised after app deployment; this change does not publish the hosted app.
