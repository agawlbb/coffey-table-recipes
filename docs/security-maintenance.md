# Workflow security maintenance

Reviewed October 13, 2026. All GitHub Actions in the web and iOS workflows are
pinned to exact commits resolved from their existing major-version tags:

- actions/checkout v4: `11d5960a326750d5838078e36cf38b85af677262`
- actions/upload-artifact v4: `ea165f8d65b6e75b540449e92b4886f43607fa02`

Review upstream changes and update these hashes deliberately. Version comments
are documentation; they do not control which code executes.

The next web/iOS builds use Flutter 3.47.7. Its hotfix corrects iOS accessibility
frames for OverlayPortal and VoiceOver focus for ReorderableListView. These
widgets are not directly used in this app's source, but framework widgets may
use them internally. Source:
https://github.com/flutter/flutter/blob/3.47.7/CHANGELOG.md

No app release, hosted app deployment, or macOS build was triggered for this
maintenance. Before the next iOS release, obtain the owner's explicit approval
for each paid macOS workflow run, run the release checks, and verify VoiceOver
focus/targeting on menus and recipe controls. Real iOS validation remains pending.

Validation: all seven offline iOS configuration/web deployment tests passed.
All four workflow files across both repositories parsed successfully, and all
nine action references were verified to use full commit hashes. Application
source code was unchanged; no local SDK upgrade was performed.
