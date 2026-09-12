# Ape X Strength

Ape X Strength is an iOS workout planner and training log built with SwiftUI. It helps athletes create reusable workouts, track every set during a session, recover an interrupted workout, and review progress over time.

## Features

- Email registration, verification, sign-in, and password recovery
- Custom exercises with configurable muscles, tracking types, and rest targets
- Reusable workout templates with planned sets, tags, ordering, and alternate exercises
- Active workout tracking with autosaved draft recovery
- Rest timer notifications and a Live Activity/Dynamic Island countdown
- Workout history, statistics, and lifetime or previous-session comparisons
- Weight and distance unit preferences
- Local Core Data persistence with authenticated API synchronization
- Archive and restore flows for workouts and exercises

## Requirements

- macOS with Xcode installed
- iOS 18.2 or later deployment target
- The Ape X Strength backend running locally or at a reachable URL

The app has no third-party package dependencies.

## Getting started

1. Clone this repository.
2. Start the separate **Ape X Strength Backend** project and note its base URL.
3. Open `Ape X Strength.xcodeproj` in Xcode.
4. Select the **Ape X Strength** scheme and an iPhone Simulator or connected device.
5. Configure `APE_X_STRENGTH_API_URL` if the backend is not available at the default URL.
6. Build and run the app.

The default API base URL is:

```text
http://127.0.0.1:5000/v1
```

To override it in Xcode, open **Product > Scheme > Edit Scheme > Run > Arguments**, add `APE_X_STRENGTH_API_URL` under **Environment Variables**, and set it to the backend's `/v1` URL.

When running on a physical iPhone, `127.0.0.1` refers to the phone itself. Use a backend address reachable from the device, such as your Mac's local-network IP address:

```text
http://192.168.1.10:5000/v1
```

## Building from the command line

List the available destinations:

```sh
xcodebuild \
  -project "Ape X Strength.xcodeproj" \
  -scheme "Ape X Strength" \
  -showdestinations
```

Build for an installed Simulator by replacing the device name if needed:

```sh
xcodebuild \
  -project "Ape X Strength.xcodeproj" \
  -scheme "Ape X Strength" \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build
```

## Testing

Run the unit and UI test suites from Xcode with **Product > Test**, or from the command line:

```sh
xcodebuild \
  -project "Ape X Strength.xcodeproj" \
  -scheme "Ape X Strength" \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test
```

The test targets cover authentication, calculations and edge cases, models and settings, repository behavior, persistence, migrations, performance, and the central workout UI flow.

Before a release, also follow the hands-on checks in [ManualTest.md](ManualTest.md).

## Project structure

```text
Ape X Strength/
├── Application/              App navigation and lifecycle integration
├── Core/
│   ├── DependencyInjection/  Live, preview, and UI-test dependencies
│   ├── DesignSystem/         Reusable components, colors, and typography
│   ├── Persistence/          Core Data stack and store setup
│   ├── Repositories/         Workout and exercise data access
│   └── Services/             Authentication, sync, settings, and timers
├── Features/
│   ├── Exercises/            Exercise library and editing
│   ├── Settings/             Preferences, sync, and account controls
│   └── Workouts/             Templates, active sessions, and history
└── Shared/                   Shared models and UI states

RestTimerWidget/              Rest-timer Live Activity extension
Ape X StrengthTests/          Unit and persistence tests
Ape X StrengthUITests/        End-to-end UI tests
```

## Architecture and data flow

The app uses SwiftUI views and view models backed by repository protocols. `AppDependencies` assembles the production, preview, and UI-testing implementations. Training data is stored locally in Core Data, so the local database remains usable if a sync attempt fails. Authenticated changes are synchronized with the backend through a versioned `/v1` API, and session credentials are stored in the Keychain.

## UI testing

Launching the app with the `-ui-testing` argument skips the authentication gate and uses an isolated in-memory store with seeded workout data. The shared Xcode scheme configures this automatically for the UI test target.

## Release checks

- Run all unit and UI tests.
- Complete the procedure in [ManualTest.md](ManualTest.md) on a Simulator and a physical iPhone.
- Verify authentication and synchronization against the intended backend environment.
- Verify notification permission behavior and the rest-timer Live Activity on a supported device.
