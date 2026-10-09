# Repository workflow

The user requests that all future project changes be committed to Git.

- Commit completed changes after appropriate verification. Include documentation and meaningful validation in the commit where applicable.
- Keep credentials, local Firebase configuration, signing keys, generated builds and personal import source files out of Git.
- This repository contains the Flutter app. The PHP server is a separate repository at `C:\xampp\htdocs\CoffeyTableRecipes`. When changing both, commit each repository independently.
- Do not push or create remote repositories unless the user requests it. Do not overwrite unrelated changes or rewrite existing history.

# Hosted development workflow

- The user selected coffeybean.com as the testing backend host. Retain the local PHP project and database for future development.
- Before future work that changes the database structure or backend API, explain the planned change and ask whether the user wants to switch the apps back to the local database/API. Do not switch automatically.
