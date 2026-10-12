# AGENTS.md

Guidance for coding agents (Claude Code, Codex, etc.) working in this repository.

## Project

Boring Notch is a macOS SwiftUI app that turns the MacBook notch into a dynamic island with music controls, calendar, a file shelf, HUDs, battery status and (in this fork) Nothing / CMF earbud controls. Deployment target is macOS 14, built with Xcode 26. Dependencies come from Swift Package Manager and are resolved automatically by `xcodebuild`.

## Build and run

```bash
# Build (Release, ad-hoc signed)
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Release \
  -derivedDataPath build/DerivedData ENABLE_HARDENED_RUNTIME=NO build

# Run
open build/DerivedData/Build/Products/Release/boringNotch.app
```

- **Always pass `ENABLE_HARDENED_RUNTIME=NO` for local builds.** No development team is set, so builds are ad-hoc signed. With the hardened runtime on, library validation rejects the embedded `MediaRemoteAdapter.framework` and the app crashes at launch with `Library not loaded … not valid for use in process`. Don't "fix" this by editing signing settings in `project.pbxproj`.
- To check that code compiles without producing a runnable app, add `CODE_SIGNING_ALLOWED=NO` and use a throwaway `-derivedDataPath`.
- Quit any running copy before launching a new build (`pkill -x boringNotch`). Launch crashes show up in `~/Library/Logs/DiagnosticReports/boringNotch-*.ips`.
- There are no unit or UI test targets. To verify a change, build it, then run the app and look at the notch.

## Layout

| Path | What lives there |
| --- | --- |
| `boringNotch/boringNotchApp.swift` | App delegate, window setup, startup of managers |
| `boringNotch/ContentView.swift` | Notch shape, open/close and hover logic, tab content slot and its height calculation |
| `boringNotch/models/BoringViewModel.swift` | Notch state (open/closed, sizes, popover-active flags) |
| `boringNotch/BoringViewCoordinator.swift` | Current tab, sneak peeks, expanding views |
| `boringNotch/enums/generic.swift` | `NotchViews` (the tabs) and other shared enums |
| `boringNotch/models/Constants.swift` | All `Defaults.Keys` (user settings) |
| `boringNotch/sizing/matters.swift` | Notch and window sizes, corner radii |
| `boringNotch/components/` | SwiftUI views: `Notch/`, `Tabs/`, `Settings/`, `Shelf/`, `Calendar/`, `Live activities/`, `Onboarding/` |
| `boringNotch/managers/` | Singleton managers (music, volume, brightness, calendar, battery, webcam) |
| `boringNotch/MediaControllers/` | Now Playing / Apple Music / Spotify / YouTube Music backends |
| `boringNotch/NothingEar/` | Nothing / CMF earbuds: BLE transport, protocol codec, `DeviceManager`, notch tab and settings page |
| `BoringNotchXPCHelper/` | XPC service target bundled into the app |
| `mediaremote-adapter/` | Prebuilt `MediaRemoteAdapter.framework` and its Perl helper |
| `boringNotch/Localizable.xcstrings` | Localized strings (synced with Crowdin) |

## Conventions

### UI: match the existing notch style
New notch UI should look like `NotchHomeView`, `BoringCalendar` and `BatteryMenuView`, not like a separate design system:
- Use system text styles (`.headline`, `.subheadline`, `.callout`, `.caption`), not fixed point sizes or `design: .rounded`. Primary text is `.white`; secondary text is `.gray` or `Color(white: 0.65)`.
- Put content directly on the black notch. Avoid bordered cards and custom chip styles.
- Use `HoverButton` for icon buttons. For segmented choices, copy the capsule-and-`matchedGeometryEffect` pattern from `TabSelectionView`.
- Use `Color.effectiveAccent` / `Color.effectiveAccentBackground` for accents, never `Color.accentColor` directly. These respect the user's custom accent setting.
- Popovers follow `BatteryMenuView`: `.padding()`, a fixed width of about 280 to 290, a `.headline` title, native controls (`Toggle(.switch)`, `Picker`, `Slider`), and `Divider` between sections.
- Image corner radii come from `MusicPlayerImageSizes.cornerRadiusInset` and honour `Defaults[.cornerRadiusScaling]`.

### Notch sizing
The open notch has a fixed height (`openNotchSize`). Tab content must fit the slot computed in `ContentView.NotchLayout()` (`openContentHeight`). Keep padding *inside* a tab's root view: padding outside it changes the reported height and makes the black background overflow.

### Popovers inside the notch
The notch closes when the mouse leaves it, and an open popover counts as leaving. Any view that presents a popover must set a flag on `BoringViewModel` while the popover is open (see `isBatteryPopoverActive` and `isEarPopoverActive`), and that flag must be included in `ContentView.isPopoverActive`. Reset the flag in `onDisappear`.

### Settings
Add new settings as `Defaults.Keys` in `models/Constants.swift` and read them with `@Default(...)` or `Defaults[...]`. Settings pages are `Form` with `.formStyle(.grouped)` under `components/Settings/`.

### Nothing Ear
- `DeviceManager.shared` is the single source of truth. Views read `deviceManager.state` and call `set…` methods; they never talk to the transport directly.
- Gate every control on `state.capabilities.supports…`, because different models support different features.
- Bluetooth must not start before onboarding finishes. Starting it is what triggers the macOS permission prompt.
- Protocol byte mappings live in `NothingProtocol.swift`. Only change them with evidence from a device capture.

### Other
- Add user-facing strings in SwiftUI `Text("…")` form so they're picked up by `Localizable.xcstrings`.
- Match the surrounding code's style: 4-space indentation, `// MARK: -` sections, and comment density similar to nearby files.
- Only `boringNotch/NothingEar/`, `boringNotch/private/` and `BoringNotchXPCHelper/` are file-system synchronized folders, so new files there are picked up automatically. Everywhere else is a classic Xcode group, and a new Swift file must also be added to `boringNotch.xcodeproj` or it won't compile into the app.
- Upstream contributions go to the `dev` branch (see `CONTRIBUTING.md`). `build/` is gitignored, so never commit build output.
