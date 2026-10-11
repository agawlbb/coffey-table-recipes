# Repository workflow

The user requests that all future project changes be committed to Git.

- Commit completed changes after appropriate verification. Include documentation and meaningful validation in the commit where applicable.
- Keep credentials, local Firebase configuration, signing keys, generated builds and personal import source files out of Git.
- This repository contains the Flutter app. The PHP server is a separate repository at `C:\xampp\htdocs\CoffeyTableRecipes`. When changing both, commit each repository independently.
- Do not push or create remote repositories unless the user requests it. Do not overwrite unrelated changes or rewrite existing history.

# Hosted development workflow

- "Create a release" explicitly authorizes reviewing changes since the prior release, choosing and tagging an appropriate version, pushing the release, rebuilding web/Android/unsigned iOS, publishing the hosted app, and saving the mobile packages on the user's desktop. Remove obsolete CoffeyTableRecipes APK/unsigned IPA release packages there only after the replacements are verified. Retain unrelated files and signed packages. Record release validation in Git.

- Unless the user specifies otherwise, all changes to database data, database structure, and the backend hosting process occur on the hosted coffeybean.com site.
- Changes to the app itself are developed and tested locally using the XAMPP copy at `C:\xampp\htdocs\CoffeyTableRecipes`. Flutter source changes belong in this repository.
- Update the hosted app only when the user explicitly asks and a new version is tagged. A tag alone does not authorize deployment.
- Use coffeybean.com as the testing backend. Retain the local PHP project, database, and API for future development.
- Use the Codex built-in browser for work whenever possible. Use Chrome only to investigate Chrome-specific problems identified by the user.
