# SignMe

An iPhone app for logging work hours and turning them into signed monthly timesheets.

Built with SwiftUI and SwiftData, iOS 17+.

## Features

- **Jobs & projects**: organise hours by employer and project
- **Live timer**: start/stop tracking, or log entries by hand (overnight shifts supported)
- **Work calendar**: see every project at a glance, log quickly, set up regular shifts, view insights
- **Planned tasks**: schedule work with reminders; it's logged only after you confirm it's done
- **Signed exports**: monthly A4 timesheets as PDF (with your saved signature) or CSV, for one project or several at once, with reusable export templates
- **Backup & restore**: export and re-import all data as JSON
- **Personalisation**: light/dark mode, 7 built-in themes plus a custom theme editor, a customisable Home screen and 10 alternate app icons

## Requirements

- Xcode 16 or later
- iOS 17.0+ (iPhone)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (optional, to regenerate the project)

## Getting started

```bash
git clone <repo-url>
cd SignMe
open SignMe.xcodeproj
```

To run on a device, select the **SignMe** target → *Signing & Capabilities* and pick your own team
(and, if needed, change the bundle identifier).

The Xcode project is generated from `project.yml`. After adding or removing files, regenerate it with:

```bash
xcodegen generate
```

## Tests

Unit tests live in `SignMeTests/`. Run them in Xcode with ⌘U, or from the command line:

```bash
xcodebuild test -project SignMe.xcodeproj -scheme SignMe \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

## Project layout

```
SignMe/
  App/         App entry point and root view
  Models/      SwiftData models (Job, Project, WorkEntry, PlannedTask, …)
  Views/       Screens
  Components/  Reusable views (signature pad, cards, sheets, …)
  Services/    Export, backup, timer, calendar, notifications
  Support/     Theme, palettes, settings, layout
  Resources/   Bundled fonts
SignMeTests/   Unit tests
Design/        App icon sources (gen.py renders the SVGs from palettes.json)
project.yml    XcodeGen spec
```

## Credits

Fonts: [Plus Jakarta Sans](https://github.com/tokotype/PlusJakartaSans) and
[Source Serif 4](https://github.com/adobe-fonts/source-serif), both under the SIL Open Font License
(see `SignMe/Resources/Fonts/`).
