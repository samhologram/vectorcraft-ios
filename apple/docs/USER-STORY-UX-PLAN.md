# VectorCraft: user-story UX validation, iPadOS and iOS

Current-build launch regression must pass before broad stories. Parent reports duplicate UIKit Paste Match Style shortcut fixed; the first Luna run used stale dd-core and is invalid evidence for current build. New stories authored, not compiled/run by Astra. Foreign-format editable-copy workflow remains documented unimplemented; no native persistence UX claim is made.

## Story-to-test matrix

| User goal | iPadOS executable case | iOS executable case / gap | Required observable result |
|---|---|---|---|
| Draw editable vector artwork | `UserStoryUITests/testDrawRectangleUndoRedoPortrait` (new) | Same selector | Rectangle gesture changes undo action; one undo/redo restores action; full screen preserves canvas and exit |
| Organize artwork without losing edits | `UserStoryUITests/testLayerVisibilityUndoRedoAndPanelReopenPortrait` (new) | Same selector, Layers sheet with reachable dismissal | Same layer visibility label changes, undo/redo restores original/edited state after reopen |
| Add, collapse, hide and reopen inspector panels | `PanelDockUITests/testShowCollapseReopenAndHide`; portrait/landscape `PanelTourUITests` | New layer story verifies phone sheet reopen; portrait panel tour for all content | Added/reopened tab hittable, body expanded; hide removes body |
| Light/dark + all tools/menu commands | `VectorCraftUITests/testSmokeLight`, `testSmokeDark`; tool/command tours | Same portrait suites | Read notes; old smoke logs are not outcome assertions |
| Persist and import a drawing | Native-save/reopen/import UI story still missing | Same gap | Native roundtrip plus foreign-source hash/copy identity must be verified independently |

## Execution and evidence rules

Astra authored/reviewed these cases on 2026-10-24; Luna executes. New cases are **not yet runtime validated**. Sol owns production fixes and generic `build-for-testing`; regenerate XcodeGen to include new files. Use current `apple/build/dd`, never an old `dd-core` bundle.

1. Shared iPad `81A653B3-9027-4C16-8335-320CB937C66C` first: portrait, then landscape, then genuinely resized narrow window if available. Shared iPhone `FF7E37C5-12E6-483D-8887-D09D18EEB4A4` only after iPad fixes. One simulator under workspace `.sim.lock`; no build while holding it.
2. Run `-only-testing:VectorCraftUITests/<Class>/<method>` with the names above, `-collect-test-diagnostics never`. No screenshots. Retain assertion text, hierarchy/frames, logs and notes. Remove app/runner after each run per cookbook.
3. Record build path/commit, device, window size, orientation, appearance, fixture/permission state, exact selector, completed/failed/aborted, first failing step and full error. A skipped case, early return, missing fixture or NOT-REACHED is **not** a passed workflow.
4. Photos integration needs a known seeded asset and explicit granted/denied/limited states. Native-copy tests need known source bytes/hash, produced native URL and repeat-open identity. Demo data proves editing UI only. Never touch a personal library fixture.
5. Compare tap count only for the same route and setup. Review clipped/hittable frames, selection traits, return-to-canvas, sheet dismissal and contextual actions. System menu rows under 44pt alone are not UX bugs. Menu plus hardware shortcut is legitimate duplication; the user rejected parallel floating panel launchers.

## Remaining cross-platform acceptance work

- Reorder/stack and collapsed/selected panel state across app termination **without reset launch arguments**; PhotoCraft already has a reusable persistence case. Repeat Window/menu route separately from dock Add; selected tab must scroll into view when already selected, collapsed or previously hidden.
- Real narrow-window resizing (Stage Manager/Split View), landscape transitions mid-edit, dark/light and large Dynamic Type. Orientation alone is not proof of resizable-window support. Accessibility evidence cannot establish contrast/color correctness without render inspection; no screenshots requested.
- Hardware shortcuts and multi-finger undo/redo must show document changes, not just menu presence. Pencil hover/squeeze/pressure and physical keyboard behavior need an appropriate device pass; list unavailable hardware as unverified, not successful.
- Native document/library persistence and import/export roundtrip beyond available tests, error recovery, permission denial and media relinking. Unsupported features remain tracked gaps.

## Bounded UX review findings

| Priority | Platform | Evidence / reproduction | Interpretation and next action |
|---|---|---|---|
| P1 | iPad / all platforms at risk | Vector shortcut duplicate caused launch crash; earlier runtime used stale dd-core | Root reports source fix + regression; Luna must run current bundle before UX suite |
| P1 | Light iPad | Masking Add → Subject did not create mask; later Crop/Remove failed after cached original absolute path became stale | Root reports repairs; rerun F and tour on fresh current bundle; no cascade counted as separate proven defect |
| P2 | Film iPad | Portrait 834pt tried to find wide dock (`>=900`) | Test setup defect fixed with landscape case and separate portrait sheet story |
| P2 | Fig iPad | New Design duplicate query failed to open document | Test fixture fixed via hittable candidate plus strict demoReady/canvas; await current run |
| P2 | iOS and iPadOS | Legacy smoke steps often log missing action as notes; iPad-only panel tests skip/return on phone | New strict result stories reduce false green; inspect legacy notes and keep remaining phone gaps explicit |

This report incorporates parent/Luna observations, not an independent runtime pass. Each new failure must be classified as product defect, test defect or unavailable fixture before a production change.

## Current-bundle runtime evidence reviewed by Astra

Read `apple/build/results/luna-smoke.log` (Luna verified current bundle UUID `9C6B0886-CB8C-3855-975A-AF4167656641`). Dark smoke completed in 95.087 seconds, proving launch survived; it did not prove full UX success: both panels were NOT-REACHED, Select found no enabled command, fullscreen was not found. Light exceeded the 120-second limit and later emitted offscreen/unchanged-history notes; classify it incomplete even though the outer suite printed passed.

The old panel helper awaits `panelTitle` after iPad moved to `panelBody.<id>`: confirmed test defect, owner repairing. Select's command query enumerated context-toolbar ids such as object.ungroup/paint.swap; menu query scoping and dismissal require hierarchy review before treating absence as a product bug. Hidden shortcut buttons have accessibilityHidden(true) in source, so duplicate hidden-node interference is unconfirmed. These findings do not close fullscreen, rectangle or menu UX coverage.

## Focused execution handoff

After the app owner rebuilds the complete test bundle and Luna obtains the shared lock, run from `vectorcraft-ios/apple` (choose a fresh result path):

```sh
xcodebuild test-without-building -scheme VectorCraft -derivedDataPath build/dd \
  -destination 'id=81A653B3-9027-4C16-8335-320CB937C66C' \
  -only-testing:VectorCraftUITests/UserStoryUITests/testLayerVisibilityUndoRedoAndPanelReopenPortrait \
  -collect-test-diagnostics never -resultBundlePath build/results/story-ipad.xcresult
```

Substitute other exact selectors from the matrix. After iPad fixes pass, repeat applicable cases with destination `id=FF7E37C5-12E6-483D-8887-D09D18EEB4A4` and a distinct result bundle. Use the existing orchestrator lock/uninstall wrapper; this command alone does not acquire the workspace lock. Require the requested test name and a nonzero completed-test count in results: exit zero with zero executed tests is not a pass.

Luna follow-up: six CatalogConsistencyTests passed, including the reserved system paste shortcut regression. Focused dock command exited zero with **zero tests executed**; the current test binary contained only smoke selectors. Owner must regenerate/rebuild before any dock/new-story claim. This is a test-bundle discovery/build issue, not a passing dock test.

## Phase 2 evidence review (2026-10-24)

- **Film iPad:** read `filmcraft-ios/apple/build/results/luna-story-suite.log`; three requested cases executed and failed. Landscape width precondition passed, but dock `menu.panels` existed and was not hittable. Portrait `menu.more` was absent. Split added a clip (strict assertion passed), then `command.edit.undo` was absent: cut is observed, undo/redo remains unreached. Portrait hierarchy in `/tmp/film-story-attachments/D9415F75-5DA6-4D1D-92CD-75EF5E5C0557.txt` has editing/transport controls but no navigation bar/Undo. Source DemoApp → DemoWindow → EditorScene has no NavigationStack while PadEditorView supplies Undo/More only through toolbar. **P1 fixture-host hypothesis:** demo may omit toolbar navigation host; sent to Film owner. Do not infer an undo-engine defect or generalize to normal DocumentGroup. Landscape dock hit testing needs separate frame evidence.
- **Fig iPad:** read `figcraft-ios/apple/build/results/luna-dock-final.log`: one case executed, failed before demo at dynamic button enumeration with stale element index 10. This is a setup failure; no dock assertions reached. Fig owner owns a stable exact-label New Design retry helper and replacement in both dock and new opacity story. No independent all-buttons opener should be reintroduced.
- **Vector:** latest Luna report confirms six catalog consistency tests passed, including reserved paste shortcut regression. Dock run executed zero tests because test binary lacked that selector. Require regenerated project/current test binary, nonzero count and named selector; a green process exit is not runtime UX proof.
- **Photo:** new phone stories are source-authored only, not compiled/executed. The no-screenshot reusable cases are EditCopy, NewFromPhoto, PlacePhoto, Fullscreen and UserStory S1–S9. Do **not** schedule legacy PhotoCraftUITests/testScreenshotsDark or testScreenshotsLight: their `shot` helper calls XCUIScreen.main.screenshot(), contrary to this run's request.
- **Light:** no new phase-2 runtime evidence reviewed. F and current-original-path tour need Luna rerun; previous reports do not establish success of the rebuilt fixes.
