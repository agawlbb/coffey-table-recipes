# Repository workflow

The user requests that all future project changes be committed to Git.

- Commit completed changes after appropriate verification. Include documentation and meaningful validation in the commit where applicable.
- Keep credentials, local Firebase configuration, signing keys, generated builds and personal import source files out of Git.
- This repository contains the Flutter app. The PHP server is a separate repository at `C:\xampp\htdocs\CoffeyTableRecipes`. When changing both, commit each repository independently.
- Do not push or create remote repositories unless the user requests it. Do not overwrite unrelated changes or rewrite history without explicit authorization.

# Hosted development workflow

- Obtain the user's explicit approval every time before triggering a GitHub Actions build on a macOS runner because it costs money. This includes new runs, reruns, and pushes or tags that trigger such builds automatically. A request to create a release does not waive this approval requirement.
- "Create a release" explicitly authorizes reviewing changes since the prior release, choosing and tagging an appropriate version, pushing the release, rebuilding web/Android/unsigned iOS, publishing the hosted app, saving the latest Android APK in the accessible "recipe app" folder, and saving the unsigned iOS IPA on the user's desktop. Remove obsolete release packages from their respective destinations only after replacements are verified. Retain unrelated files and signed packages. Record release validation in Git.
- On every release, update `CHANGELOG.md` with the version, release date, and meaningful changes since the previous release. Its initial history was reconstructed from Git tags and release records in 0.5.0. Include the changelog in the release commit before tagging; do not invent unsupported history.
- The Android release destination is `G:\My Drive\recipe app`. Save the latest verified APK there instead of on the desktop.

- Unless the user specifies otherwise, all changes to database data, database structure, and the backend hosting process occur on the hosted coffeybean.com site.
- Deploying and pushing changes to the hosted backend and database are authorized without additional permission within the requested work, including Git pushes needed for backend deployment.
- Changes to the app itself are developed and tested locally using coffeybean.com as the backend. PHP source remains at `C:\xampp\htdocs\CoffeyTableRecipes`. Flutter source changes belong in this repository.
- Update the hosted app only when the user explicitly asks and a new version is tagged. A tag alone does not authorize deployment.
- Outside an instruction to "create a release", obtain explicit permission before pushing or deploying the hosted app. An instruction to "create a release" authorizes hosted app deployment; macOS GitHub Actions builds still require separate approval every time.
- Use coffeybean.com as the testing backend. Retain the local PHP source for development. The backend and persistent MySQL database are hosted exclusively; the outdated local recipe database was retired on 2026-10-11.
- Use the Codex built-in browser for work whenever possible. Use Chrome only to investigate Chrome-specific problems identified by the user.
