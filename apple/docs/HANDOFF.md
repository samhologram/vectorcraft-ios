# VectorCraft iOS checkpoint — 2026-10-24

## Compiled state

- The native SwiftUI app and UI test runner compile for generic arm64 iOS Simulator from `apple/build/dd`.
- The launch crash was traced in the simulator log to a duplicate Cmd-Option-Shift-V keyboard shortcut: UIKit's Paste and Match Style and the generated Paste on All Artboards command. The system shortcut is reserved; Paste on All Artboards remains in the Edit menu and command palette. The generated Window and Help items again extend the system groups.
- The iPad inspector has persistent stacked tab groups, explicit Add and Close actions, collapse and menu reorder, and scroll-to-selected group/tab. The phone sheet still uses `PanelHost` and `PanelSwitcher`.
- The bridge parser and integration test expectations now match the catalog: opaque `albumId | null` stays JSON, and a rectangle remains a `Rectangle` layer after saving and reopening.

## Verification and limits

- Bridge host: 11 unit and 11 integration tests passed; clippy with `-D warnings` passed. Command ID, tool and panel mapping, and generated feature coverage checks passed before this checkpoint.
- `xcodebuild build-for-testing` passed after regenerating XcodeGen and includes `PanelDockUITests` and `UserStoryUITests` in the test runner.
- The current `build/dd` iPad dark smoke launched and finished, but its notes marked panel opening, Select-menu action, and fullscreen as not reached. The old test helper expected the removed single-panel `panelTitle`. It has since been updated for dock IDs and hittable duplicate identifiers, and the bundle rebuilt; that revised behavior has not yet been run.
- The light smoke did not establish workflow success; its run was stopped after about 120 seconds. No new crash was confirmed in that run.
- Six catalog consistency tests passed, including the duplicate-shortcut regression, in the previous `build/dd` unit run. The later UndoManager test-fixture correction compiled but has not been executed.
- Focused dock and user-story tests are compiled but have not yet run. iPad first, then iPhone. Do not treat a missing element, note, skipped test, or early return as a passed workflow.

## Known product gaps

- Dock action menus and several panel bodies currently expose duplicate actions; consolidate once the dock interaction passes. Drag reorder is not implemented; the menu offers reorder controls.
- Generic catalog panels may show an empty state; the panel tour must distinguish an open page from a working action.
- Device media import, the app-owned document folder and editable foreign-format copies remain specified in `CONTRACT.md` but are not implemented. iPhone workflow and physical-device verification remain pending.
- The generated top-level Object/Type/Select/Effect menu order and Window/Help merge should be inspected in a live menu; a successful build alone does not establish menu layout.

## Next validation

Run iPad smoke, `PanelDockUITests`, catalog/unit tests, and Astra's two `UserStoryUITests` from `apple/build/dd` under the workspace simulator lock. Read their notes and accessibility frames; fix any real product or test-navigation failure. Then run portrait/landscape tours and the iPhone suite. Preserve `-collect-test-diagnostics never` and the no-screenshot rule for this pass.
