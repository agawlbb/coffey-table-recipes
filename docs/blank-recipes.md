# Blank recipes

Choose **Blank recipe** on Add recipe. Enter a recipe name and at least one browse category. A photo and Favorite this recipe are optional. The editor uses the same upload, camera, crop/rotate, cover selection and photo removal controls as other recipes. Creating or saving a blank recipe does not call recipe AI, image AI or category artwork generation.

Blank recipes appear in normal browsing, category browsing, search and favorite filters. Open one to edit its name/category/photos, delete it with the existing undo/trash behavior, or update individual and household favorites. The edit pencil opens the simplified name/category/photo editor.

Choose **Import recipe** to use the existing Text, Website, File or Camera import workflow. Review and save to fill the same recipe; its ID, favorites, existing pictures and categories are retained. Canceling or a failed import leaves the saved blank unchanged. Revision checks protect against concurrent edits. Regular imports continue to use their existing AI workflow.

Blank recipes use `source_type: blank` in the existing schema. The authenticated `POST /households/{id}/recipe-blank` endpoint returns an unsaved draft and the category catalog; the existing recipe save endpoint persists it. The backend enforces name/category requirements. Blank recipes have no cooking content or nutrition. Neither share-link creation nor the public recipe webpage accepts a blank recipe. After import the recipe can be shared normally.

Validation: Flutter analysis; blank recipe/import/editor/favorite/photo/browser/search/sharing tests; PHP blank recipe fixtures plus existing relationship, favorite, sharing and photo checks. No app build or app deployment is part of this feature.
