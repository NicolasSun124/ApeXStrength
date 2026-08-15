# Ape X Strength — Feature and Learning Guide

## Scope and how to read this guide

This guide is based on the Swift source, Core Data model, widget target, and test suites in this repository. Each feature includes:

- **What it does**
- **Key functions/types** used to implement it
- **Design logic/structure**
- **Why this design was chosen**, where the intent is supported by the implementation. When the repository does not explicitly document the reason, the explanation is marked as an inference.
- **Learning requirements**: the concepts someone should understand to rebuild or extend the feature.

The app is a local-first SwiftUI application. Its broad structure is:

`SwiftUI View → ObservableObject ViewModel → Repository protocol → Core Data repository → persistent store`

Small preferences use `UserDefaults`; rest timers additionally use ActivityKit and local notifications.

## 1. App shell, navigation, and dependency injection

### What it does

Starts the app, selects live or UI-test dependencies, and exposes Workouts, Exercises, and Settings as three tabs in a forced dark theme.

### Key functions/types

- `Ape_X_StrengthApp.init()` chooses `AppDependencies.uiTesting` when `-ui-testing` is present, otherwise `AppDependencies.live`.
- `Ape_X_StrengthApp.body` injects `appDependencies` and the Core Data `managedObjectContext` into SwiftUI's environment.
- `RootTabView.body` builds the `TabView` and constructs each top-level view model.
- `AppDependencies.live`, `.preview`, and `.uiTesting` compose persistence, repositories, settings, and sync services.
- `AppDependenciesKey` and `EnvironmentValues.appDependencies` create a custom environment dependency.

### Design logic/structure

The app uses manual dependency injection rather than creating repositories inside views. Protocol-typed dependencies (`any WorkoutRepository`, `any ExerciseRepository`, and service protocols) isolate UI code from Core Data. Separate live, preview, and UI-test compositions supply production data, in-memory preview data, and deterministic test fixtures.

### Why this design

This makes view models testable and SwiftUI previews/UI tests repeatable. The reason is strongly evidenced by the dedicated `preview` and `uiTesting` dependency graphs. `NoOpSyncService` also reserves an architectural seam for future synchronization without shipping incomplete network behavior.

### Learning requirements

- SwiftUI app lifecycle, `Scene`, `WindowGroup`, `TabView`, and `NavigationStack`
- Environment values and custom `EnvironmentKey`s
- Protocol-oriented dependency injection and existential types (`any Protocol`)
- `@MainActor`, `@State`, and `@StateObject`
- Test/preview dependency composition

## 2. Shared design system and asynchronous UI states

### What it does

Provides consistent colors, spacing, corner radii, typography, buttons, cards, fields, tags, and loading/empty/error states across the app.

### Key functions/types

- `ApeColor`, `ApeSpacing`, `ApeRadius`, and `Font` extensions define tokens.
- `ApePrimaryButtonStyle.makeBody` and `ApeSecondaryButtonStyle.makeBody` standardize controls.
- `ApeCard`, `ApeFormField`, `ApeTextFieldStyle`, and `ApeTag` compose reusable UI.
- `ViewLoadState` models `.idle`, `.loading`, `.loaded`, and `.failed`.
- `ApeLoadingView`, `ApeEmptyState`, and `ApeErrorState` render common states.

### Design logic/structure

Screens compose semantic components rather than repeating raw padding, color, and border values. View models publish a small load-state enum so views can switch predictably between progress, content, empty, and failure presentations.

### Why this design

Central tokens reduce visual drift and make global restyling inexpensive. Explicit load states prevent contradictory booleans such as “loading and failed” from coexisting.

### Learning requirements

- SwiftUI custom `View`, `ButtonStyle`, and `TextFieldStyle`
- Generic view builders (`@ViewBuilder`, generic `Content: View`)
- Design tokens and component-driven UI
- Enum-based state machines
- Accessibility labels, hints, Dynamic Type, and semantic colors

## 3. Core Data persistence and local user

### What it does

Stores exercises, muscles, tags, workout templates, planned sets, active/completed sessions, session exercises, and performed sets. It also initializes one local user and supports full data reset.

### Key functions/types

- `PersistenceController.init(inMemory:storeURL:)` configures `NSPersistentContainer`, inferred lightweight migration, merge policy, and optional in-memory storage.
- `initializeTemporaryUser()` fetches or creates the local profile.
- `resetUserData()` deletes the user's sessions, workouts, custom exercises, and tags and clears hidden exercises.
- Core Data entities: `User`, `Muscle`, `Exercise`, `Tag`, `WorkoutTemplate`, `TemplateExercise`, `TemplatePlannedSet`, `WorkoutSession`, `SessionExercise`, and `SessionSet`.
- Repository helpers use `context.fetch`, `existingObject(with:)`, `NSPredicate`, `NSSortDescriptor`, `NSOrderedSet`, `context.save()`, `rollback()`, and deletion rules.

### Design logic/structure

Templates and performed sessions are separate object graphs. Ordered join entities (`TemplateExercise`, `SessionExercise`) preserve exercise order and attach occurrence-specific data. Planned and completed sets are child entities with cascade deletion. Session exercise fields snapshot names, tracking configuration, muscle information, and rest targets.

### Why this design

Separating templates from session records lets a workout evolve without rewriting history. Snapshot fields preserve historical meaning after an exercise is renamed or reconfigured. Ordered relationships plus explicit `position`/`setNumber` values provide stable presentation order. Automatic lightweight migration is appropriate for additive/simple schema changes.

### Learning requirements

- Core Data entities, relationships, inverses, delete rules, and generated classes
- `NSManagedObjectContext`, fetch requests, predicates, sort descriptors, and object IDs
- Ordered versus unordered relationships
- Transaction-like save/rollback patterns
- Lightweight migration and persistent store configuration
- Data modeling for immutable history versus editable templates

## 4. Exercise library, search, and detail

### What it does

Lists visible exercises, searches them by name, shows tracking/rest/muscle details, and navigates to exercise detail.

### Key functions/types

- `ExercisesViewModel.load()` calls `ExerciseRepository.fetchExercises()` and publishes `ViewLoadState`.
- `ExercisesView` derives filtered results from `searchText`, presents list cards, detail navigation, and create flow.
- `ExerciseDetailViewModel.load()`, `archive()`, and `showExercise(id:)` manage detail state.
- `CoreDataExerciseRepository.fetchExercises()`, `fetchExercise(id:)`, and `exerciseListItem(_:)` map managed objects into view data.
- `restLabel(_:)` formats seconds for display.

### Design logic/structure

Managed objects do not flow directly into SwiftUI. Repositories map them to immutable `ExerciseListItem` and `ExerciseDetail` models identified by `NSManagedObjectID`. Search is performed locally over the already-loaded list.

### Why this design

DTO-style models keep views independent from managed-object lifecycle and faulting. Client-side filtering is simple and responsive for a small local library; this is an implementation inference rather than an explicitly documented decision.

### Learning requirements

- `List`/`ScrollView`, `NavigationLink`, `.searchable`, sheets, and toolbars
- Observable view models and published state
- Derived collection filtering and sorting
- Mapping persistence entities to presentation models
- Stable identity with `Identifiable` and `NSManagedObjectID`

## 5. Create, edit, copy, archive, and restore exercises

### What it does

Creates custom exercises with name, rep type, difficulty type, rest duration, primary muscle, and secondary muscles. Custom exercises can be edited; global exercises use “Copy & Edit.” Deletion is soft archival, and archived exercises can be restored.

### Key functions/types

- `CreateExerciseViewModel.load()` loads muscles and, in edit/copy mode, existing details.
- `toggleSecondary(_:)` maintains secondary-muscle selection while keeping the primary choice exclusive.
- `save()` validates input and calls `createExercise(_:)` or `updateExercise(id:input:)`.
- `ExerciseConfiguration.storageValue` and `init(storageValue:)` encode/decode rep+difficulty configuration, including a legacy `reps_weight` value.
- `MuscleSelectionView.select(_:)` handles single or multiple selection.
- Repository functions: `fetchMuscles()`, `createExercise(_:)`, `updateExercise(id:input:)`, `archiveExercise(id:)`, `restoreExercise(id:)`, `apply(_:to:)`, and `editableExercise(id:)`.
- `ArchivedExercisesView.load()` and `restore(_:)` implement recovery UI.

### Design logic/structure

The form owns editable strings/selections in its view model and converts them into a validated `NewExercise` command. Global exercises are protected from direct mutation: copy mode creates a user-owned version. Archival preserves references from templates and historical sessions instead of deleting the row.

### Why this design

Protecting global exercises maintains a consistent built-in library, while copying allows personalization. Soft deletion avoids breaking relational history and enables recovery. The storage codec preserves backward compatibility with an earlier tracking-type value.

### Learning requirements

- Form validation and two-way SwiftUI bindings
- Single- and multi-select UI with `Set`
- Domain enums and backward-compatible serialization
- Ownership/authorization rules in repositories
- Soft deletion and archival UX

## 6. Workout list, search, tags, and statistics

### What it does

Lists workouts ordered by recent update, searches by name, displays tag chips, and summarizes usage and performance statistics.

### Key functions/types

- `WorkoutsViewModel.load()` calls `fetchWorkouts()`.
- `WorkoutsView` filters by `searchText` and renders workout cards and metric tiles.
- `CoreDataWorkoutRepository.fetchWorkouts()` fetches non-archived templates and derives session statistics.
- `workoutStatistics(from:)` computes means for duration, volume, rest, intensity, and completion.
- `TagColor.init(name:)` assigns known tags across a palette and hashes custom names to deterministic HSL-derived RGB colors; `TagColor.rgb(...)` performs conversion.
- Formatting helpers in `WorkoutsView` display absent statistics as placeholders.

### Design logic/structure

Statistics are calculated from completed sessions when workout list items are assembled. Tags are many-to-many Core Data entities, but color is derived rather than stored. Missing statistics remain optional and render as unavailable.

### Why this design

Derived tag colors keep custom tags visually stable without adding persistence fields. Optional averages distinguish “no history” from a real zero. Computing summaries during fetch keeps display views simple, though a larger data set may eventually justify aggregate queries or cached summaries.

### Learning requirements

- Many-to-many relationships
- Collection aggregation (`map`, `compactMap`, `reduce`, mean calculations)
- Optional data presentation
- Deterministic hashing and HSL-to-RGB color conversion
- Date/number formatting and local search

## 7. Create and edit workout templates

### What it does

Creates or edits a named workout; selects and reorders exercises; assigns tags; adds/removes planned sets; records rep/time/distance and resistance targets; and configures alternate exercises.

### Key functions/types

- `CreateWorkoutViewModel.load()` fetches exercises/tags and hydrates edit state from a preview.
- `addExercises(_:)`, `removeExercises(at:)`, `moveExercises(from:to:)`, and `reorderExercises(_:)` manage ordered selection.
- `addSet(to:)`, `removeSet(_:from:)`, and `setBinding(for:setID:)` manage per-exercise `WorkoutSetDraft`s.
- `replaceExercise(_:with:)` swaps an exercise while updating alternate selections.
- `addTag(named:)` and repository `createTag(named:)` normalize/deduplicate tags.
- `save()` validates and converts form strings into `NewWorkout`/`NewPlannedSet`, then calls `createWorkout(_:)` or `updateWorkout(id:input:)`.
- `CreateWorkoutView` uses exercise, tag, alternate, and reorder sheets.
- Reorder wrappers implement `UIViewControllerRepresentable`, `UITableViewDataSource`, and `UITableViewDelegate` row movement.

### Design logic/structure

Each selected exercise owns a dictionary entry of draft sets keyed by exercise object ID. Each draft set has a temporary UUID so SwiftUI can bind/edit it before persistence. The repository rebuilds the ordered template child graph and assigns explicit positions/set numbers.

### Why this design

Temporary form models avoid inserting partial Core Data objects while the user is editing or cancels. Join entities are necessary because planned sets, order, and alternates belong to an exercise's occurrence in one workout, not to the global exercise itself. UIKit table reordering is used to obtain explicit drag-to-reorder behavior; this is inferred from the bridge implementation.

### Learning requirements

- Complex SwiftUI form state and dictionary-backed bindings
- Parsing/validating numeric text into `Int`, `Double`, and `Decimal`
- Temporary IDs and command/input models
- Ordered many-to-many modeling with join entities
- `UIViewControllerRepresentable` and coordinator/delegate bridging
- Transactional create/update logic

## 8. Workout preview and inline template editing

### What it does

Shows workout tags, exercises, planned sets, and previous performance values. It can start/resume the workout, open full editing, archive the template, remove/reorder exercises or sets, manage alternates, and replace exercises.

### Key functions/types

- `WorkoutPreviewViewModel.load()` calls `fetchWorkoutPreview(id:)` and `fetchAvailableExercises()`.
- `archive()`, `removeExercise(id:)`, `reorderExercises(_:)`, `setAlternateExercises(_:for:)`, `replaceExercise(_:with:)`, and `removeSet(number:from:)` call corresponding repository mutations and reload.
- `fetchWorkoutPreview(id:)` combines planned sets with `latestSessionSets(for:)` to seed display values from the most recent completed occurrence.
- `WorkoutPreviewView.startSession()`, `loadResumableDraft()`, and `sessionDidClose()` control session presentation.
- Presentation helpers select columns based on `ExerciseRepType` and format decimals/time.

### Design logic/structure

The preview is a read model assembled from template configuration plus latest performance history. Mutations live in the repository, while the view model turns thrown errors into user-facing state and refreshes the read model after changes.

### Why this design

Showing previous values reduces repetitive data entry and provides an immediate target. Reload-after-mutation favors correctness and a single source of truth over manually patching many nested view fields.

### Learning requirements

- Read-model composition across related entities
- Error propagation from throwing repositories to published UI state
- Conditional UI based on domain configuration
- Sheets, confirmation dialogs, full-screen covers, and navigation
- Refresh-after-write consistency patterns

## 9. Active workout execution and set tracking

### What it does

Runs a workout session with an elapsed timer. Users edit reps/time/distance/weight, mark sets complete, add sets/exercises, remove or reorder exercises, configure/choose alternates, and finish or abort.

### Key functions/types

- `ActiveWorkoutView` transforms a `WorkoutPreview`/draft into local `ActiveWorkoutExercise` and `ActiveWorkoutSet` state.
- `exerciseCard(exercise:)` chooses the appropriate editable performance field based on `repType` and resistance field based on `difficultyType`.
- `addExercise(_:)`, `removeExercise(_:)`, `setAlternates(_:for:)`, and `replaceExercise(_:with:)` mutate the live occurrence list.
- `editableInteger`, `editableDecimal`, `timeButton`, `savePickedTime`, `performanceTitle`, and `performanceValue` implement typed editing and display.
- `currentSessionExercises()` maps live UI state into persistence commands.
- `finishSession(shouldSave:rating:note:)`, `abortSession()`, and `closeFinishedSession()` control completion/discard.
- `TimelineView`-driven helpers `elapsedTime(at:)` and `restTime(at:endDate:)` derive timer text from dates.

### Design logic/structure

The active screen uses value-type local state for fast editing, then serializes the entire current exercise/set graph through `CompletedSessionExercise`. The repository replaces stored session contents atomically. Exercise occurrences have UUID UI identity, allowing duplicate occurrences to remain distinct even when they point to the same exercise.

### Why this design

Date-derived timers remain accurate through render pauses/backgrounding, unlike decrementing an integer on every tick. Whole-draft replacement simplifies synchronization of add/remove/reorder actions and is protected by repository rollback. Occurrence identity avoids collapsing duplicate exercises, a behavior explicitly covered by tests.

### Learning requirements

- Nested value-type state and `Binding`
- `TimelineView` and date-based timer calculation
- Keyboard/focus management and numeric input
- Mapping UI state into persistence commands
- Stable occurrence identity versus domain-object identity
- Full-screen workflow state machines and destructive confirmations

## 10. Active-session autosave, recovery, resume, and discard

### What it does

Persists unfinished workouts, autosaves changes/background transitions, detects the newest active draft on launch/return, and offers Resume or Discard.

### Key functions/types

- `WorkoutRepository.startSession(...)` creates an unfinished `WorkoutSession` (`endedAt == nil`).
- `updateActiveSession(id:exercises:)` replaces draft contents and updates duration.
- `fetchActiveSessionDraft()` fetches the newest unfinished session for the local user and reconstructs preview/completion state.
- `discardSession(id:)` removes an abandoned draft.
- `WorkoutsViewModel.detectActiveSessionDraft()`, `discardActiveSessionDraft()`, and `clearActiveSessionDraft()` drive the recovery prompt.
- `ActiveWorkoutView.autosaveSession()` persists current values.
- Scene-phase/task hooks in the active and list flows trigger save/recovery checks.

### Design logic/structure

Completion state is encoded by whether `endedAt` is nil. Recovery is global to the user and deliberately selects only the newest unfinished session. Draft data contains completed set numbers so checkmarks can be restored.

### Why this design

Using the same session entity for drafts and completed records avoids a parallel draft schema. Newest-only recovery resolves multiple interrupted drafts deterministically. Autosave and background handling protect workout data against interruptions; these cases have dedicated unit, UI, and manual tests.

### Learning requirements

- App lifecycle and `scenePhase`
- Async `.task` work and `@MainActor`
- Autosave/debouncing considerations
- Draft recovery queries and deterministic conflict selection
- Idempotent save/discard operations
- UI restoration from persisted state

## 11. Rest timer, notifications, Live Activity, and Dynamic Island

### What it does

Starts a per-exercise rest countdown, allows ±15-second adjustment/cancel, restores an unexpired timer for the same session, optionally schedules a local notification, and mirrors the timer in a Live Activity/ Dynamic Island widget.

### Key functions/types

- `ActiveWorkoutView.startRestTimer(seconds:)` and `clearRestTimerWhenFinished()` coordinate UI lifecycle.
- `RestTimerCoordinator.start(until:workoutName:sessionIdentifier:)` persists the deadline, creates/updates an ActivityKit activity, requests notification permission if needed, and schedules `UNNotificationRequest`.
- `restoredEndDate(for:defaults:now:)` restores only a matching, unexpired session timer and clears stale state.
- `cancel()`, `finish()`, `clearPersistedTimer()`, and `endActivity()` clean up notifications/activity/state.
- `RestTimerView.adjust(by:)` changes the deadline; countdown helpers derive text from the end date.
- `RestTimerLiveActivity.body` defines Lock Screen and Dynamic Island presentations.
- `NotificationDelegate.userNotificationCenter(...)` permits foreground notification presentation.

### Design logic/structure

Only the absolute `endDate` and owning session identifier are persisted. UI, notification trigger, and Live Activity all share that deadline. User notification preference is stored separately in the settings service; Live Activity operation is gated by system authorization.

### Why this design

An absolute deadline survives suspension and avoids tick drift. Session scoping prevents a timer from one workout appearing in another. Central coordination keeps pending notifications, persisted state, and ActivityKit lifecycle consistent.

### Learning requirements

- ActivityKit `ActivityAttributes`, content state, Live Activities, and Dynamic Island regions
- WidgetKit extension targets
- `UNUserNotificationCenter`, authorization, triggers, and delegate behavior
- Async/await APIs and main-actor coordination
- Deadline-based timer math and restoration
- Shared model definitions across app/widget targets

## 12. Session completion, rating, notes, and save/discard

### What it does

Shows a workout summary, accepts a 1–5 rating and optional note, presents progress comparisons, and asks whether to save or discard the session.

### Key functions/types

- `WorkoutFinishView` owns `rating`, `note`, comparison choice, and confirmation/error state.
- `exerciseImprovementCard(_:)`, `metricRow`, and `metricColor` render trend results.
- `finish(shouldSave:)` invokes the active view's completion callback.
- `ActiveWorkoutView.finishSession(...)` creates `CompletedWorkoutSession` and calls `saveCompletedSession(_:)`, or discards the draft.
- `normalizedNote(_:)` turns whitespace-only notes into nil.
- `replaceContents(of:with:completedAt:)` snapshots exercise data, converts weight to pounds, calculates volume and completion percentage, and persists ordered sets.

### Design logic/structure

The finish UI is separated from persistence through callbacks. The repository calculates derived session facts at the point of save. Stored weights are normalized to pounds; display converts back to the current user-selected unit.

### Why this design

Confirmation prevents accidental loss or unintended history creation. Canonical weight storage avoids mixed-unit records. Snapshotting at save keeps historical sessions readable after future exercise edits.

### Learning requirements

- Modal workflow composition and callback closures
- Input normalization
- Canonical-unit persistence and presentation conversion
- Derived-field calculation and immutable historical snapshots
- Confirmation and recoverable error UX

## 13. Improvement analytics

### What it does

Compares the current workout against either the previous session or lifetime history and classifies each metric as improved, maintained, regressed, or first entry.

### Key functions/types

- `calculateImprovements(for:)` collects completed current sets and completed historical occurrences.
- `completedSets(from:)` maps Core Data sets to calculation models.
- `improvementMetrics(current:historical:configuration:)` selects relevant metrics by rep/difficulty type.
- `metricTitles(for:)`, `maximumPerformance(in:repType:)`, `performanceComparisonText`, and formatting helpers build results.
- `trend(_:comparedWith:)` treats larger values as better.
- `inverseTrend(_:comparedWith:)` treats lower assistance as better.
- `ImprovementTrend`, `ExerciseImprovementSummary`, `ExerciseImprovementMetrics`, and `ImprovementMetric` model the output.

### Design logic/structure

The primary metric is max reps, time, or distance. Weighted work adds max weight; weighted reps also add volume weight. Assisted work uses minimum assistance and inverted comparison. Performance is compared at the current resistance when possible. Only completed sets count.

### Why this design

Metrics adapt to what “better” means for each exercise configuration. Ignoring incomplete sets avoids treating planned/abandoned work as performance. Inverse assistance logic captures that needing less help is progress. Both previous and lifetime comparisons serve short-term and all-time context.

### Learning requirements

- Domain-driven analytics and metric definitions
- Generic comparable functions
- Decimal arithmetic and unit-aware formatting
- Filtering and aggregating historical data
- Edge cases: missing history, empty completed sets, equal values, and inverse metrics

## 14. Session history and detail

### What it does

Lists completed sessions newest-first and shows duration, volume, completion, rating, note, exercise snapshots, and set-by-set performance.

### Key functions/types

- `WorkoutSessionHistoryViewModel.load()` calls `fetchSessionHistory()`.
- `WorkoutSessionHistoryView.sessionCard(_:)` renders summary cards.
- `WorkoutSessionDetailView.exerciseCard(_:)`, `detailRow`, `performanceTitle`, and `performanceValue` render historical detail.
- `fetchSessionHistory()` filters `endedAt != nil`, sorts descending, prefers snapshot values, and falls back to current exercise values for older records.
- `duration(_:)` and `decimal(_:)` format values.

### Design logic/structure

History reads immutable DTOs, not managed objects. Snapshot fields are optional for migration compatibility; fallback logic allows sessions saved before snapshots existed to remain displayable.

### Why this design

Historical truth should not change when a template/exercise changes. Optional snapshot fallback supports schema evolution without invalidating old data. Fetching newest-first matches typical training-review behavior.

### Learning requirements

- Historical read models and snapshotting
- Backward-compatible fallback logic
- Nested navigation and read-only tabular UI
- Date, duration, percentage, and decimal formatting
- Fetch ordering and performance considerations

## 15. Settings, unit preferences, archives, reset, and About

### What it does

Stores weight/distance units and rest-alert preference, links to archived workouts/exercises, displays app metadata, and supports guarded destructive data reset.

### Key functions/types

- `SettingsViewModel.settings.didSet` calls `SettingsService.save(_:)`.
- `UserDefaultsSettingsService.load()` and `save(_:)` persist lightweight preferences.
- `WeightUnit.pounds(fromDisplayed:)` and `displayed(fromPounds:)` convert using `Decimal`.
- `DistanceUnit.init(setting:)` validates distance preference (distance conversion is not yet implemented elsewhere).
- `ArchivedWorkoutsView.load()/restore(_:)` and exercise equivalents expose soft-deleted data.
- `ResetDataConfirmationView.isConfirmed` requires the exact phrase `RESET DATA` before invoking `resetUserData()`.
- `AboutView.informationRow(...)` presents version/app information.

### Design logic/structure

Preferences are separated from relational training data. Changes save immediately through `didSet`. Destructive reset is isolated in a confirmation sheet and requires typed confirmation.

### Why this design

`UserDefaults` fits small non-relational preferences. Immediate persistence keeps settings simple and durable. Typed confirmation adds friction proportional to irreversible deletion. Archives separate reversible removal from full reset.

### Learning requirements

- `UserDefaults` and service abstraction
- Property observers and immediate persistence
- Measurement conversion with `Decimal`
- Safe destructive-action UX
- Bundle metadata/version display
- Understanding implemented versus preparatory settings (distance unit is currently preparatory)

## 16. Archiving and restoration of workouts

### What it does

Soft-deletes workout templates from the main list and restores them from Settings.

### Key functions/types

- `archiveWorkout(id:)` and `restoreWorkout(id:)` toggle `isArchived`, update `updatedAt`, and mark `syncState`.
- `fetchArchivedWorkouts()` filters archived templates and sorts by name.
- `WorkoutPreviewViewModel.archive()` translates errors for the UI.
- `ArchivedWorkoutsView.load()` and `restore(_:)` provide restore actions.

### Design logic/structure

Archival is a state transition rather than physical deletion. Archived records are excluded from normal fetches but retain relationships and sessions.

### Why this design

It preserves history, prevents accidental permanent loss, and leaves room for future synchronization of deletion state.

### Learning requirements

- Soft-delete predicates
- State transitions and sync markers
- Confirmation dialogs and restore interfaces
- Referential integrity

## 17. Sync-ready state (not an active user feature yet)

### What it does

The schema and repository mutations attach `serverID`, `clientUUID`, `syncState`, and `syncedAt` fields, but actual synchronization is currently a no-op.

### Key functions/types

- `SyncService.syncIfNeeded()` defines the boundary.
- `NoOpSyncService.syncIfNeeded()` intentionally does nothing.
- Repository writes set values such as `pendingCreate` and `pendingUpdate`.
- Most entities contain client/server identifiers and sync state.

### Design logic/structure

Local writes are already marked for a future synchronization engine, and networking is hidden behind a service protocol.

### Why this design

This is preparatory architecture: it makes later backend integration less invasive while keeping the current release local-only. It should not be described as shipped cloud sync.

### Learning requirements

- Offline-first synchronization concepts
- Client-generated IDs, server IDs, dirty-state tracking, and conflict resolution
- Idempotent API design and retry queues
- Protocol-backed service substitution

## 18. Automated and manual quality coverage

### What it does

Validates repository persistence, migrations, calculations, draft recovery, interruptions, ordering, duplicate occurrences, accessibility, UI workout flow, and large-history performance.

### Key functions/types

- `RepositoryPersistenceTests` covers create/fetch/archive/restore, active drafts, newest-draft recovery, and duplicate occurrences.
- `CalculationsAndEdgeCaseTests` covers statistics, improvement rules, assistance inversion, unit conversion, timer boundaries/recovery, interruption saves, and DST/time-zone behavior.
- `MigrationAndPerformanceTests` reopens persistent stores with migration options and measures large-history fetches.
- `CentralWorkoutFlowUITests` runs start/complete/save, interruption, accessibility naming, and Dynamic Type flows.
- `RepositoryFixture` creates in-memory users, exercises, workouts, inputs, and completed sessions.
- `ManualTest.md` provides release-oriented manual cases and a test record.

### Design logic/structure

Repository tests use in-memory Core Data, migration tests use a real temporary store, UI tests use deterministic seeded dependencies, and manual tests cover device/system behaviors that are difficult to assert completely in unit tests.

### Why this design

Each test layer targets a different failure class: pure calculations, persistence behavior, full UI journeys, migration/scale, and real-device accessibility/background behavior.

### Learning requirements

- XCTest unit, performance, and UI testing
- In-memory versus disk-backed Core Data fixtures
- Dependency injection for deterministic tests
- Accessibility identifiers and Dynamic Type testing
- Migration, DST/time-zone, interruption, and performance test design

## Cross-cutting function flow examples

### Create an exercise

`CreateExerciseView` → `CreateExerciseViewModel.save()` → `ExerciseRepository.createExercise(_:)` → `CoreDataExerciseRepository.apply(_:to:)` → `NSManagedObjectContext.save()` → list reload

### Create a workout

`CreateWorkoutView` → `CreateWorkoutViewModel.save()` → construct `NewWorkout` → `createWorkout(_:)`/`updateWorkout(id:input:)` → create ordered `TemplateExercise` and `TemplatePlannedSet` graph → save → preview/list reload

### Run and save a workout

`WorkoutPreviewView.startSession()` → `startSession(...)` → `ActiveWorkoutView` edits local values → `autosaveSession()`/`updateActiveSession(...)` → `WorkoutFinishView` → `saveCompletedSession(_:)` → snapshots + statistics fields → history/list fetch

### Start a rest timer

set completion → `startRestTimer(seconds:)` → absolute end date → `RestTimerCoordinator.start(...)` → persist deadline + ActivityKit + optional notification → `RestTimerLiveActivity` and in-app countdown render from the same date

## Suggested learning order

1. Swift language fundamentals: structs/classes/enums, optionals, protocols, closures, generics, collection transforms, errors, and concurrency.
2. Basic SwiftUI: view composition, navigation, lists, forms, sheets, state, bindings, and observable objects.
3. The app's shared models and design system.
4. Core Data fundamentals and this project's entity graph.
5. Repository pattern and dependency injection.
6. Exercise CRUD and settings as smaller vertical slices.
7. Workout-template creation and ordered relationships.
8. Active-session state, autosave, recovery, and history snapshots.
9. Analytics and unit conversion.
10. Notifications, ActivityKit, WidgetKit, and lifecycle edge cases.
11. Unit/UI/migration/performance/accessibility testing.

## Important implementation boundaries

- The app is currently local-first with a temporary local profile; sign-in/profile editing are placeholders.
- `SyncService` exists, but `NoOpSyncService` means remote sync is not implemented.
- Weight conversion is implemented and used by repositories. Distance preference is stored, but distance conversion is not currently applied.
- Workout mean-rest and mean-intensity fields exist, but this codebase does not currently populate those values during session completion; their list statistics may therefore remain unavailable.
- Archiving is recoverable soft deletion; Reset Data is the destructive operation.
