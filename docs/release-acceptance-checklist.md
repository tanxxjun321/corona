# Corona Release Acceptance Checklist

Use this checklist for the first website-distributed release.

## Build And Signing

- `swift test` passes.
- `xcodebuild -project Corona.xcodeproj -target CoronaApp -configuration Debug build` passes.
- `SIGN_IDENTITY` is a Developer ID Application certificate.
- `NOTARY_PROFILE` is a valid `notarytool` keychain profile.
- `make release` completes.
- `codesign --verify --deep --strict --verbose=2 .build/app/Corona.app` passes.
- `spctl --assess --type execute --verbose=2 .build/app/Corona.app` passes.
- `.build/dist/Corona-release.zip` is the downloadable artifact.

## Permissions

- First launch without Accessibility shows the required-permission state.
- Hidden/move/scan actions are disabled until Accessibility is granted.
- Granting Accessibility makes Scan Results usable.
- Screen Recording denied: Hidden Panel and Scan Results show fallback icons/text.
- Screen Recording granted and previews enabled: Hidden Panel and Scan Results show real menu bar item thumbnails.
- Screen Recording revoked: refreshing Hidden Panel and Scan Results returns to fallback icons/text.

## Hide, Reveal, And Recovery

- Show/hide hidden section works from the menu bar item.
- Turning off "Show main menu bar icon" hides Corona's own status item immediately; turning it back on restores it.
- With the main icon hidden, launching Corona again (Finder/Spotlight/`open`) re-opens the main panel showing the "menu bar icon is hidden" banner with a working "Show Menu Bar Icon" button.
- Hidden main-icon state persists across app restarts (icon stays hidden after relaunch until re-enabled).
- Saving a layout and relaunching restores the saved layout.
- Hidden Panel Reveal moves an item to visible.
- Timer auto re-hide returns the revealed item to its original hidden section.
- Relaunch with pending relocation restores pending items before applying saved layout.
- A failed move does not leave the mouse button or drag state stuck.
- Failed apply retry and warning (force failures by launching with `CORONA_DISABLE_DIRECT_MENU_BAR_MOVE=1`, e.g. `CORONA_DISABLE_DIRECT_MENU_BAR_MOVE=1 .build/app/Corona.app/Contents/MacOS/Corona`, with a saved layout that needs moves): the startup restore retries 3 times (~1s/3s/8s apart — watch for `main.applySession retryScheduled` log lines), then gives up and shows a warning status-item icon (filled triangle); opening the main panel shows a persistent orange error in the footer.
- With the warning showing, relaunch without the env var and drag any item: the apply succeeds and both the warning icon and the panel error clear.
- While a retry is scheduled (within ~12s of a failed apply), drag an item in the panel: no second apply runs concurrently (log shows `main.applySession supersedeScheduledRetry` or `main.applySession coalesced`), and the latest layout is what ends up applied.
- Normal move: mouse is suppressed only during the move (~1s) and is fully responsive immediately after.
- Stall the main thread during a move (e.g. pause the process in the debugger or open a modal dialog mid-move): the move times out, mouse suppression lifts automatically within ~3 seconds (watchdog), and subsequent moves still work.

## App Coverage

- Test at least three third-party menu bar apps.
- Test one item with Screen Recording previews unavailable.
- Test one app quit/relaunch while its item has a pending relocation.
- Do a basic check on the primary display with external displays disconnected.
- Do a basic check with an external display connected, without relying on advanced multi-display placement.
