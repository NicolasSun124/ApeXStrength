# Ape X Strength — Architecture and Design Principles

## Purpose

This document explains the overarching software-design principles used in Ape X Strength. It is written as interview preparation: each section describes the idea, identifies where it appears in the project, explains why it fits, and calls out tradeoffs or limitations an interviewer may ask about.

The shortest architectural summary is:

`SwiftUI View → ObservableObject ViewModel → Repository protocol → Core Data implementation`

Supporting services handle preferences, timers, notifications, and future synchronization. The application is local-first and uses manual dependency injection.

## 1. Model–View–ViewModel (MVVM)

### What it is

MVVM separates an interface into:

- **Model:** domain data and business concepts.
- **View:** visual presentation and user interaction.
- **ViewModel:** presentation state and operations that connect the view to the model layer.

In SwiftUI, a view normally observes a view model and redraws when its published state changes.

### Where it is used

- Views include `WorkoutsView`, `WorkoutPreviewView`, `ExercisesView`, `ExerciseDetailView`, `CreateExerciseView`, `SettingsView`, and `WorkoutSessionHistoryView`.
- View models include `WorkoutsViewModel`, `WorkoutPreviewViewModel`, `CreateWorkoutViewModel`, `ExercisesViewModel`, `ExerciseDetailViewModel`, `CreateExerciseViewModel`, `SettingsViewModel`, and `WorkoutSessionHistoryViewModel`.
- Presentation models include `WorkoutListItem`, `WorkoutPreview`, `ExerciseListItem`, `ExerciseDetail`, and `WorkoutSessionHistoryItem` in `Shared/Models/AppModels.swift`.
- SwiftUI owns view-model lifetime with `@StateObject`; view models expose changes through `ObservableObject` and `@Published`.

For example, `ExercisesView` displays `ExercisesViewModel.exercises`. The view model's `load()` method asks `ExerciseRepository` for data and converts success or failure into view state.

### Why it was chosen

MVVM fits SwiftUI's reactive rendering model. It keeps fetch/save/error-handling code out of basic view layout, makes view models testable without rendering UI, and provides a clear place for presentation-specific state.

### Important nuance

The project uses **pragmatic rather than strict MVVM**. `ActiveWorkoutView` owns substantial local workflow and transformation logic, including autosave, timer coordination, and completion mapping. Archived-list views also call repositories directly. This is reasonable for view-local behavior, but it means the architecture is not uniformly “all logic in view models.”

In an interview, do not claim perfect MVVM. A stronger answer is: “The app broadly follows MVVM, while highly interactive or small screens retain local SwiftUI state. If those flows grow, I would extract an `ActiveWorkoutViewModel` or session coordinator.”

### Likely interview question

**Why not put every piece of logic in a view model?**

Because extracting trivial display and ephemeral interaction state can add indirection without improving reuse or testing. Long-lived business state, persistence, and error handling benefit from extraction; temporary sheet visibility or focus state usually does not.

## 2. Separation of concerns and layered architecture

### What it is

Separation of concerns gives each layer one primary kind of responsibility. The project roughly separates:

- `Application`: startup and top-level navigation
- `Features`: user-facing screens and feature view models
- `Shared/Models`: domain and presentation data
- `Core/Repositories`: persistence-facing business operations
- `Core/Persistence`: Core Data setup and lifecycle
- `Core/Services`: settings, sync boundary, timers, and notifications
- `Core/DesignSystem`: reusable visual language
- Widget, unit-test, and UI-test targets

### Where it is used

The folder structure directly reflects these boundaries. A feature view does not configure an `NSPersistentContainer`, and `PersistenceController` does not know how workout cards are rendered.

### Why it was chosen

The boundaries make the code easier to locate, reason about, test, and replace. They also reduce the chance that changes in one concern—such as the database schema—force changes throughout every view.

### Tradeoff

Every layer adds types and navigation overhead. For a small app, excessive layering can become ceremony. This project keeps the layering relatively light: there is no separate use-case/interactor class for every action.

## 3. Dependency injection

### What it is

Dependency injection means a type receives the collaborators it needs instead of constructing them internally. This is inversion of control: object creation happens at a composition root.

### Where it is used

- `AppDependencies` owns persistence, workout/exercise repositories, settings, and sync services.
- `AppDependencies.live`, `.preview`, and `.uiTesting` are separate dependency graphs.
- `Ape_X_StrengthApp` selects a graph and injects it through `EnvironmentValues.appDependencies`.
- `RootTabView` passes repositories/services into view models and views.
- View-model initializers accept protocol-typed repositories or services.
- `RestTimerCoordinator` accepts a notification center and settings service, with production defaults.

### Why it was chosen

Dependency injection enables:

- in-memory persistence for tests and previews;
- deterministic seeded UI tests;
- replacement of Core Data repositories with test doubles;
- central control over object lifetime;
- future replacement of `NoOpSyncService` with a real implementation.

### Why manual injection instead of a framework

The graph is small enough that explicit construction remains readable. A dependency-injection framework would add runtime behavior and another abstraction without solving a current complexity problem.

### Tradeoff

The environment provides convenient global access below the app root, so dependencies can become less visible if every child reads them directly. This project largely avoids that by passing specific dependencies into feature constructors.

### Likely interview question

**What is the difference between dependency injection and the service-locator pattern?**

Constructor injection makes dependencies explicit in a type's API. A service locator lets a type pull arbitrary dependencies from a global registry. SwiftUI's environment can behave like either; this app uses it primarily to transport a composed dependency container at the root and then explicitly passes narrower dependencies onward.

## 4. Dependency inversion and protocol-oriented design

### What it is

The Dependency Inversion Principle says high-level policy should depend on abstractions rather than concrete low-level implementations. Swift protocols provide those abstractions.

### Where it is used

- `WorkoutRepository` is implemented by `CoreDataWorkoutRepository`.
- `ExerciseRepository` is implemented by `CoreDataExerciseRepository`.
- `SettingsService` is implemented by `UserDefaultsSettingsService`.
- `SyncService` is currently implemented by `NoOpSyncService`.
- View models depend on `any WorkoutRepository`, `any ExerciseRepository`, or `any SettingsService`, not on Core Data/UserDefaults classes.

### Why it was chosen

The UI layer cares about operations such as “fetch workouts” or “save settings,” not how they are stored. Protocol boundaries allow persistence to change and make focused test doubles possible.

### Tradeoff

Protocols should represent meaningful substitution points. Creating a protocol for every concrete type would add indirection. Here, protocols are concentrated around external boundaries—persistence, preferences, and synchronization—where replacement is useful.

## 5. Repository pattern

### What it is

A repository exposes domain-oriented data operations while hiding database mechanics. It acts like a collection/service for aggregate data from the caller's perspective.

### Where it is used

`WorkoutRepository` exposes operations such as:

- `fetchWorkouts()`
- `fetchWorkoutPreview(id:)`
- `createWorkout(_:)`
- `startSession(...)`
- `updateActiveSession(...)`
- `saveCompletedSession(_:)`
- `calculateImprovements(for:)`

`ExerciseRepository` similarly owns exercise fetching, creation, editing, archiving, restoration, and muscle lookup.

Concrete repositories contain the Core Data requests, predicates, relationship construction, unit conversion, statistics, snapshots, save/rollback behavior, and managed-object mapping.

### Why it was chosen

Repositories stop Core Data details from leaking into views and most view models. They create a single place for persistence rules such as visibility predicates, ordering, archival constraints, and canonical weight storage.

### Tradeoff and possible improvement

`CoreDataWorkoutRepository` is large and combines persistence with calculations. As the application grows, it could be split into narrower collaborators such as:

- `WorkoutTemplateRepository`
- `WorkoutSessionRepository`
- `ImprovementCalculator`
- `WorkoutStatisticsCalculator`

That would improve single responsibility, but splitting now would also increase coordination complexity. The current grouping is defensible for the project's size.

## 6. Single Responsibility Principle (SRP)

### What it is

SRP says a unit should have one primary reason to change. It does not literally mean every class can perform only one operation.

### Where it is used

- `PersistenceController` configures and manages persistence.
- `UserDefaultsSettingsService` handles preference storage.
- `RestTimerCoordinator` synchronizes timer persistence, Live Activities, and notifications.
- Feature view models manage presentation state for a feature.
- Design-system types handle styling and reusable UI.
- The widget target only renders rest-timer activity state.

### Why it was chosen

Focused types are easier to test and change. For example, notification/ActivityKit behavior can evolve without placing those APIs inside every workout view.

### Honest limitation

`CoreDataWorkoutRepository` and `ActiveWorkoutView` currently have several reasons to change. This is a useful interview discussion: SRP is a direction and tradeoff, not a rule that the code perfectly satisfies.

## 7. Composition over inheritance

### What it is

Composition builds behavior by assembling small objects and views. Inheritance builds behavior through subclass hierarchies.

### Where it is used

- SwiftUI screens compose `ApeCard`, `ApeFormField`, buttons, tags, lists, and navigation containers.
- `AppDependencies` composes concrete services and repositories.
- View models receive repository/service collaborators.
- There is almost no application-defined inheritance; necessary NSObject/delegate inheritance appears only at Apple framework interoperability boundaries.

### Why it was chosen

SwiftUI is inherently composition-oriented. Small views and protocols are more flexible than deep class hierarchies and avoid fragile superclass coupling.

## 8. Unidirectional data flow and single source of truth

### What it is

Unidirectional flow means state moves down into views and user actions/events move back up to mutate the owner of that state. A single source of truth means one owner is authoritative for a given piece of state.

### Where it is used

- View models own loaded screen data through `@Published`.
- Views observe that state and invoke view-model methods.
- Form views use `Binding` to edit state owned by the form/view model.
- `CreateWorkoutViewModel` owns `selectedExercises`, `selectedTagIDs`, `plannedSets`, and alternate IDs.
- Core Data is authoritative after a save; view models generally reload repository read models following mutations.
- `SettingsViewModel.settings` is the in-memory source while `didSet` immediately persists it.

### Why it was chosen

Predictable ownership reduces synchronization bugs and matches SwiftUI's rendering system. Reloading after nested workout mutations favors consistency over manually patching multiple cached structures.

### Nuance

The active workout deliberately has two representations: editable local value state and a persisted draft. Autosave reconciles them. That is not literally one copy of the data; rather, local state is authoritative during interaction and Core Data is the recovery source across lifecycle interruptions.

## 9. Reactive state management

### What it is

Reactive UI declares what the interface should look like for a state, rather than manually issuing commands to update individual controls.

### Where it is used

- `ObservableObject` and `@Published` notify SwiftUI about view-model changes.
- `@StateObject` preserves an observable object's lifetime across view redraws.
- `@State` owns ephemeral UI values such as sheet visibility, search text, focus, and confirmation state.
- `@Binding` allows child controls and sheets to edit parent-owned values.
- `ViewLoadState` drives loading, loaded, empty, and error presentations.

### Why it was chosen

It is the native SwiftUI model and makes screen output a function of state. This reduces imperative UI synchronization.

### Likely interview question

**Why `@StateObject` instead of `@ObservedObject` for these view models?**

The view creates/owns the view model, so `@StateObject` preserves its identity through view recomputation. `@ObservedObject` is more appropriate when a parent owns and supplies an already-created object.

## 10. Explicit state machines instead of boolean combinations

### What it is

An enum can represent mutually exclusive states that would otherwise require several booleans and permit invalid combinations.

### Where it is used

`ViewLoadState` represents idle, loading, loaded, and failed states. Domain enums similarly constrain rep type, difficulty type, weight unit, distance unit, app tab, trend, and comparison mode.

### Why it was chosen

The compiler helps enforce valid cases, switching is exhaustive, and impossible combinations such as “loading and successfully loaded” are eliminated.

### Extension opportunity

Some complex active-workout navigation currently uses multiple booleans. If that workflow grows, a single route/workflow enum could model mutually exclusive sheets and stages more explicitly.

## 11. Value semantics and immutable read models

### What it is

Swift structs have value semantics: assignment passes an independent value rather than shared object identity. Immutable read models expose `let` properties and represent a snapshot for display.

### Where it is used

- `WorkoutListItem`, `WorkoutPreview`, `ExerciseListItem`, `ExerciseDetail`, completed-session inputs, and history items are structs.
- Repository methods map mutable `NSManagedObject`s into these models.
- Temporary form/session structs are edited locally before being submitted back as commands.

### Why it was chosen

SwiftUI works naturally with lightweight value data. Mapping out of Core Data prevents views from depending on context lifetime, faulting, thread confinement, or accidental managed-object mutation.

### Tradeoff

Mapping creates extra code and copies. For the current data size, clarity and isolation outweigh that cost. Large data sets may require pagination or smaller projections.

## 12. Read models and command/input models

### What it is

Read and write needs often have different shapes. A read model is optimized for rendering; a command/input model captures a validated change to perform.

### Where it is used

- Read models: `WorkoutListItem`, `WorkoutPreview`, `WorkoutStatistics`, `ExerciseDetail`, `WorkoutSessionHistoryItem`.
- Input/command models: `NewWorkout`, `NewPlannedSet`, `NewExercise`, `CompletedWorkoutSession`, and `CompletedSessionExercise`.
- Draft models: `WorkoutSetDraft` and active workout value types.

### Why it was chosen

A workout card needs counts, tags, and aggregates, while creating a workout needs ordered exercise IDs, planned sets, and alternate IDs. Forcing one model to satisfy every use would create optional-heavy, ambiguous types.

### Interview terminology

This resembles a **lightweight CQRS-style separation**, but it is not full CQRS: reads and writes still use the same repository and Core Data store. Avoid overstating it.

## 13. Domain modeling and type safety

### What it is

Domain modeling represents meaningful business concepts explicitly instead of passing unstructured strings and dictionaries everywhere.

### Where it is used

- `ExerciseRepType` distinguishes reps, time, and distance.
- `ExerciseDifficultyType` distinguishes weighted, bodyweight, and assisted work.
- `WeightUnit`, `DistanceUnit`, `ImprovementTrend`, and `ImprovementComparison` constrain valid values.
- `ExerciseConfiguration` pairs rep and difficulty behavior and provides backward-compatible storage encoding.
- Dedicated session, set, tag, and statistics structures carry named values.

### Why it was chosen

Types make invalid values harder to represent, enable exhaustive switches, and keep configuration-dependent behavior readable.

### Limitation

Some Core Data fields remain strings because persistence schemas need stable serialized values. Conversion into enums happens at repository/model boundaries.

## 14. Local-first and offline-capable design

### What it is

A local-first app treats the on-device store as the primary source for normal interactions rather than requiring a network round trip.

### Where it is used

- Core Data stores workouts, exercises, drafts, sessions, and history.
- `UserDefaults` stores preferences and rest-timer recovery state.
- Session creation, autosave, completion, and analytics run locally.
- A temporary local user is initialized automatically.
- `SyncService` is a no-op in the current build.

### Why it was chosen

Workout tracking must remain fast and reliable in poor-connectivity environments. Local writes also make autosave and interruption recovery immediate.

### Tradeoff

Multi-device access, backup, authentication, and conflict resolution are not yet delivered. The schema contains sync metadata, but that is preparation rather than working cloud sync.

## 15. Persistence modeling: aggregates and join entities

### What it is

An aggregate groups related data that should be changed consistently. A join entity represents a relationship that has its own properties.

### Where it is used

- `WorkoutTemplate` owns ordered `TemplateExercise` occurrences.
- A `TemplateExercise` links one workout to one exercise while also storing position, planned sets, and alternate exercises.
- `WorkoutSession` owns ordered `SessionExercise` occurrences.
- A `SessionExercise` links a session to an exercise and owns completed sets plus historical snapshots.
- `TemplatePlannedSet` and `SessionSet` carry occurrence-specific values and set numbers.

### Why it was chosen

Order, planned sets, alternates, and performed values do not belong to a global exercise; they belong to its occurrence in one template/session. Explicit join entities correctly locate those responsibilities and allow the same exercise to appear in many workouts.

### Important detail

Occurrence identity is distinct from exercise identity. Active UI models use separate UUIDs so duplicate occurrences of one exercise do not collapse into a single row.

## 16. Historical snapshotting

### What it is

Snapshotting copies selected mutable reference data into a historical record when an event occurs.

### Where it is used

`SessionExercise` stores snapshot fields for exercise name, tracking type, difficulty, primary muscle name/color, and rest target. `replaceContents(of:with:completedAt:)` creates/preserves them. History fetches prefer snapshots and fall back to current exercise values for older records.

### Why it was chosen

If an exercise is renamed or reconfigured later, an old workout should still show what the athlete actually performed at the time. Snapshot fallback also maintains compatibility with sessions saved before those fields existed.

### Tradeoff

Snapshots duplicate data and require deliberate schema updates when more historical fields become important. The benefit is stable, truthful history.

## 17. Transactional persistence and rollback

### What it is

A logical write should either succeed completely or leave the prior valid state intact.

### Where it is used

Repository mutation methods commonly:

1. validate and fetch required objects;
2. build or update the complete relationship graph;
3. call `context.save()`;
4. call `context.rollback()` when saving throws.

This appears in workout/exercise creation, archival, restoration, session updates, and completion.

### Why it was chosen

Workout graphs contain several related entities. A partial write could leave invalid ordering or orphaned children. Core Data context save/rollback provides a practical unit of work.

### Nuance

`rollback()` reverses all unsaved changes in that context, not only one repository method's edits. Because the app primarily uses one main context and synchronous main-actor operations, this is manageable; larger concurrent editing flows may benefit from child/background contexts per operation.

## 18. Soft deletion and recoverability

### What it is

Soft deletion marks data as inactive instead of physically removing it.

### Where it is used

- Exercises and workout templates have `isArchived`.
- Normal fetches exclude archived rows.
- Settings links to archived lists that can restore them.
- Repository archive/restore operations toggle state and update sync metadata.
- Permanent removal is reserved for the explicit Reset Data flow.

### Why it was chosen

Archiving protects historical relationships and permits undo/recovery. It is safer for user-created training plans than immediate hard deletion.

### Tradeoff

Every relevant fetch must apply the correct archival predicate, and archived data continues consuming storage.

## 19. Canonical data representation and boundary conversion

### What it is

Canonical representation stores a measurement in one standard unit and converts only at system boundaries.

### Where it is used

- Session weights are stored in pounds.
- `WeightUnit.pounds(fromDisplayed:)` converts user input before persistence.
- `WeightUnit.displayed(fromPounds:)` converts stored values for the selected display unit.
- Calculations normalize current input to pounds before comparing it with history.

### Why it was chosen

Without normalization, changing the preference could mix kilograms and pounds in one data set and corrupt statistics. Canonical storage makes comparisons stable.

### Important limitation

Distance-unit preference is stored but corresponding distance conversion is not yet applied. An interview answer should distinguish present functionality from planned structure.

## 20. Derived state instead of duplicated state

### What it is

Derived values are calculated from authoritative inputs rather than independently persisted wherever possible.

### Where it is used

- Timer text is derived from `endDate` and the current date.
- Tag colors are deterministically derived from tag names.
- Search results are derived from loaded arrays and search text.
- Improvement trends are derived from current and historical values.
- Workout statistics are derived from completed sessions during fetch.

Some expensive/useful session summaries—duration, volume, and completion percentage—are persisted at completion.

### Why it was chosen

Derivation avoids synchronization bugs. Persisting selected session summaries is a denormalization tradeoff for convenient historical/list reads.

### Likely interview question

**When should derived data be stored?**

Store it when recomputation is expensive, the value represents a historical event-time result, or queries need it frequently. Otherwise derive it to avoid stale duplicates. If stored, define when and by whom it is recomputed.

## 21. Deadline-based timers and lifecycle resilience

### What it is

A deadline-based timer stores a target date and derives remaining time instead of decrementing a counter every second.

### Where it is used

- Active elapsed/rest UI uses date differences and `TimelineView`.
- `RestTimerCoordinator` persists an absolute end date.
- Local notification triggers and Live Activity content use the same deadline.
- `restoredEndDate(...)` validates session ownership and expiration.

### Why it was chosen

iOS may suspend the app, so a repeating in-process timer is not guaranteed to fire. A deadline remains correct after suspension, backgrounding, clock ticks, and UI redraw gaps.

### Tradeoff

Wall-clock changes must be considered. The tests explicitly exercise DST and time-zone behavior around absolute durations/order.

## 22. Lifecycle-aware autosave and recovery

### What it is

Lifecycle-aware design reacts to backgrounding, interruption, and relaunch instead of assuming a workflow completes in one uninterrupted foreground session.

### Where it is used

- An active session is persisted immediately with `endedAt == nil`.
- `updateActiveSession(...)` replaces saved draft contents.
- Active-workout lifecycle hooks autosave current values.
- `fetchActiveSessionDraft()` restores the newest unfinished session.
- The workout list presents Resume or Discard.
- Rest-timer recovery is scoped to a matching session identifier.

### Why it was chosen

Workout entry is long-running and interruption-prone. Losing completed sets after a call, background event, or process termination would be a severe UX failure.

## 23. Structured concurrency and main-actor isolation

### What it is

Swift concurrency uses `async`/`await` for asynchronous operations. `@MainActor` isolates UI-bound mutable state and main-context Core Data access to the main actor.

### Where it is used

- View models and repository protocols/implementations are `@MainActor`.
- `RestTimerCoordinator` is `@MainActor` and awaits notification/ActivityKit APIs.
- SwiftUI `.task` launches lifecycle-related asynchronous work.
- Timer restoration helpers are `nonisolated` because they operate only on supplied/default preference data.

### Why it was chosen

UI publication and the configured `viewContext` belong on the main thread/actor. Compiler-enforced isolation reduces data races. Async APIs avoid blocking while permissions, notifications, or ActivityKit work completes.

### Tradeoff and scaling concern

Large fetches/calculations on `@MainActor` could block UI. If history grows significantly, background Core Data contexts and sendable value results would be preferable.

## 24. Adapter pattern for UIKit interoperability

### What it is

An adapter converts one interface into another expected interface.

### Where it is used

Workout reorder screens use `UIViewControllerRepresentable` to host a `UITableViewController`. A nested `Coordinator` implements `UITableViewDataSource` and `UITableViewDelegate`, then writes row moves back to SwiftUI bindings.

### Why it was chosen

It provides established editable-table row movement while the rest of the feature remains SwiftUI. It also demonstrates incremental interoperability rather than rewriting an entire screen in UIKit.

### Tradeoff

The bridge adds lifecycle and state-synchronization complexity. Modern SwiftUI move/reorder APIs may eventually remove the need for it depending on deployment targets and desired interaction.

## 25. Strategy-like behavior through enums and protocols

### What it is

The Strategy pattern selects behavior based on an interchangeable policy. This project uses lightweight forms of it rather than formal strategy classes.

### Where it is used

- `ExerciseRepType` selects reps/time/distance presentation and maximum-performance calculation.
- `ExerciseDifficultyType` selects resistance behavior and whether higher or lower weight represents improvement.
- `WeightUnit` selects conversion behavior.
- Protocol implementations select persistence/settings/sync behavior at composition time.

### Why it was chosen

The behavior set is small and closed, so enums with exhaustive switches are simpler than a hierarchy of strategy objects. Protocol strategies remain appropriate where implementations are open-ended or externally replaceable.

## 26. Deterministic behavior

### What it is

Given the same inputs, deterministic logic produces the same output. This improves predictability and testability.

### Where it is used

- `TagColor(name:)` always maps a tag name to the same color.
- Fetches specify ordering through sort descriptors and explicit positions/set numbers.
- Draft recovery selects the newest unfinished session.
- UI-test dependencies seed known workout/exercise data.
- Improvement calculations follow configuration-specific rules.

### Why it was chosen

Stable ordering and appearance prevent confusing UI changes. Deterministic fixtures and calculations make failures reproducible.

## 27. Backward compatibility and schema evolution

### What it is

Backward-compatible code continues understanding data created by older versions.

### Where it is used

- Core Data enables automatic and inferred lightweight migration.
- `ExerciseConfiguration.init(storageValue:)` recognizes the legacy `reps_weight` value.
- History prefers snapshot fields but falls back to live exercise values when snapshots are absent.
- Migration tests reopen a persistent store and verify preserved data.

### Why it was chosen

Fitness history is valuable user data and should survive app upgrades. Compatibility logic makes additive schema evolution safer.

### Tradeoff

Compatibility branches accumulate over time. They should be documented and removed only when old data can no longer exist or has been migrated explicitly.

## 28. Design system and reusable components

### What it is

A design system centralizes reusable visual tokens and semantic components.

### Where it is used

- `ApeColor`, `ApeSpacing`, and `ApeRadius` define tokens.
- Font extensions define typography roles.
- `ApeCard`, `ApeFormField`, `ApeTag`, `ApePrimaryButtonStyle`, and `ApeSecondaryButtonStyle` define components.
- Shared loading, empty, and error views standardize application states.

### Why it was chosen

Centralization improves consistency, reduces repeated modifiers, and makes brand-wide changes easier. Semantic names communicate intent better than unexplained numeric values.

### Tradeoff

A design system must remain flexible. Overly rigid components lead feature code to work around the system rather than reuse it.

## 29. Accessibility as a cross-cutting requirement

### What it is

Accessibility is designed into controls, semantics, and layout rather than added only at release time.

### Where it is used

- Controls include accessibility labels and hints for actions and numeric fields.
- System controls and semantic labels are preferred where possible.
- Dynamic Type and central actions are covered in UI and manual tests.
- VoiceOver, contrast-related settings, and large text are included in `ManualTest.md`.

### Why it was chosen

Workout entry occurs under physical strain and should remain understandable and operable across different abilities and text sizes. Accessibility testing also catches general usability problems.

## 30. Testability as an architectural property

### What it is

Testability is not just writing tests; it is designing boundaries, deterministic inputs, and replaceable dependencies so behavior can be tested reliably.

### Where it is used

- Protocol-backed repositories/services allow test implementations.
- `PersistenceController(inMemory:)` provides isolated stores.
- `AppDependencies.uiTesting` seeds deterministic data.
- `RepositoryFixture` creates reusable domain fixtures.
- Pure or mostly pure helpers handle conversion, trends, formatting, and timer recovery.
- Tests cover repositories, calculations, migrations, large history, UI flow, accessibility, backgrounding, time zones, and DST.

### Why it was chosen

Persistence-heavy apps can fail at relationship, ordering, lifecycle, and migration boundaries. The architecture makes those boundaries directly exercisable.

### Testing pyramid in this project

- **Unit/repository tests:** fast business and persistence behavior.
- **Migration/performance tests:** storage compatibility and scale.
- **UI tests:** critical end-to-end journeys and accessibility reachability.
- **Manual tests:** real-device/system behaviors that automation cannot fully guarantee.

## 31. Open/Closed Principle and extension seams

### What it is

The Open/Closed Principle aims for code that can gain new behavior through extension with minimal modification to stable callers.

### Where it is used

- A new `SyncService` implementation can replace `NoOpSyncService` without changing feature callers.
- Repository implementations can be substituted behind protocols.
- New shared components can extend the design system.
- Exercise behavior is centralized around domain enums, although adding a new enum case requires updating exhaustive switches.

### Why it was chosen

External boundaries such as sync and persistence are likely to change. Stable interfaces contain that change.

### Nuance

Enums intentionally trade openness for exhaustiveness. Adding a new rep type is a source change across switches, but the compiler identifies every required update. That can be safer than silently accepting unsupported behavior.

## 32. YAGNI and intentional extension points

### What it is

YAGNI—“You Aren't Gonna Need It”—warns against building speculative functionality. Extension points are useful only when they remain cheap and grounded in plausible change.

### Where it is used or challenged

- `NoOpSyncService` is a cheap seam; no networking engine has been prematurely built.
- Sync metadata already exists on entities, reflecting anticipated backend work.
- Distance preference is persisted before full conversion behavior exists.
- Manual DI avoids adopting a heavier framework prematurely.

### Interview discussion

The app balances preparation with current scope. A protocol and a few metadata fields are low-cost seams, but each preparatory element should be revisited to ensure it still serves a concrete roadmap. Do not present unimplemented seams as completed features.

## 33. Error handling and user-safe failure

### What it is

Failures should cross layers in a controlled way and produce safe, actionable UI rather than silent corruption or crashes.

### Where it is used

- Repository methods throw domain/persistence errors.
- View models catch errors and publish `.failed` or feature-specific error messages.
- Views display alerts and allow retry/dismissal.
- Save operations roll back on failure.
- Destructive actions use confirmation dialogs; data reset requires typed confirmation.

### Why it was chosen

Persistence operations can fail, and destructive fitness-data operations carry high user cost. Explicit failure paths preserve state and communicate what happened.

### Possible improvement

Several UI messages use localized descriptions directly. A centralized mapping from domain errors to consistent, localized user messages would improve polish as the app grows.

## 34. Naming and semantic APIs

### What it is

Semantic APIs express user/domain intent rather than implementation mechanics.

### Where it is used

Repository methods say `archiveWorkout`, `calculateImprovements`, `fetchActiveSessionDraft`, and `replaceExercise`, rather than exposing generic database CRUD calls. Models use names such as `CompletedWorkoutSession` and `WorkoutSessionDraft`.

### Why it was chosen

Intent-focused names make call sites readable and allow the implementation to change without changing the language of the feature.

## Architecture tradeoffs worth discussing in an interview

### Why Core Data?

Core Data provides object graphs, ordered relationships, migrations, change tracking, and local persistence well suited to interconnected workout/session data. The tradeoff is framework complexity, context/thread rules, and verbose mapping.

### Why not use managed objects directly in views?

Presentation structs isolate SwiftUI from Core Data lifecycle/threading, make state easier to test, and allow tailored read models. The cost is mapping code and copies.

### Why keep repositories on `@MainActor`?

The current repository uses `viewContext`, and published UI state is main-actor bound. It keeps correctness simple. The tradeoff is potential UI blocking at scale; background contexts would be the next step for expensive work.

### Why replace a draft's nested contents instead of diffing every edit?

Whole-graph replacement makes add/remove/reorder behavior straightforward and ensures persisted order matches UI state. The cost is extra object churn. At current workout sizes, simplicity is likely more valuable; larger graphs or sync constraints might justify incremental diffs.

### Why use both SwiftUI and UIKit?

SwiftUI handles most composition and reactive state. UIKit is adapted only where table row-reordering behavior was useful. This is pragmatic interoperability, with the cost of bridge complexity.

### Why archive instead of delete?

Workout and exercise records participate in templates and history. Archival avoids breaking references and provides recovery. Permanent deletion remains an explicit reset action.

### Why snapshot historical data?

References show current state; history needs event-time state. Snapshots ensure old sessions do not change when an exercise is edited.

## Short interview-ready project explanation

> Ape X Strength is a local-first SwiftUI app using pragmatic MVVM. Views observe feature view models, which depend on protocol-based repositories and services injected from a central composition root. Core Data stores editable workout templates separately from performed sessions, using join entities for ordered, occurrence-specific sets and alternatives. Completed sessions snapshot mutable exercise details so history remains accurate. Active workouts are persisted as unfinished sessions and autosaved for interruption recovery. The app uses canonical weight storage, deadline-based timers, ActivityKit, local notifications, reusable design-system components, and in-memory/test-specific dependency graphs. The architecture prioritizes offline reliability, testability, and historical integrity while leaving contained extension seams for future synchronization.

## Rapid-fire interview questions and answer points

### Is this strict MVVM?

No. It is pragmatic MVVM. Most loaded/persisted feature state is handled by view models, while ephemeral SwiftUI state and some complex active-workout orchestration remain in views. The clearest refactoring candidate is an `ActiveWorkoutViewModel` or coordinator.

### What SOLID principles are visible?

- SRP through focused persistence, settings, timer, design-system, and feature types—with acknowledged large-type exceptions.
- Open/Closed through replaceable repository/service implementations.
- Liskov Substitution through protocol-conforming test/live implementations that honor the same contracts.
- Interface Segregation is partially present through separate workout, exercise, settings, and sync protocols; the workout repository could become narrower.
- Dependency Inversion through view models depending on protocols rather than Core Data implementations.

### What is the application's source of truth?

Core Data is durable truth for workout/exercise/session data. During an active edit, local SwiftUI value state is the immediate interaction truth and is reconciled to an unfinished Core Data session via autosave. UserDefaults is durable truth for lightweight preferences and timer recovery metadata.

### How does the app protect historical accuracy?

It separates templates from session records, stores ordered performed-set data, and snapshots mutable exercise metadata on session occurrences. History prefers snapshots and supports older records with fallback values.

### How is testability achieved?

Constructor/manual dependency injection, protocol boundaries, in-memory Core Data, deterministic UI-test composition, value read models, pure calculation helpers, and distinct unit/UI/migration/performance/manual test layers.

### What would you refactor first as the app grows?

1. Extract active-workout orchestration into a view model/session coordinator.
2. Split the large workout repository into template, session, and analytics responsibilities.
3. Move large fetch/calculation work to background contexts.
4. Introduce typed/localized domain-to-UI error mapping.
5. Consolidate repeated reorder/alternate-picker UI.
6. Complete distance conversion before exposing it as a meaningful preference.

### What patterns should you avoid claiming?

- Do not claim full Clean Architecture; there are no distinct use-case/interactor and domain-entity layers.
- Do not claim full CQRS; read/write models differ, but they share repositories and one store.
- Do not claim cloud sync; only a protocol, no-op service, and sync-ready metadata exist.
- Do not claim uniformly strict MVVM; several views contain workflow logic.

## Source map

- App composition: `Ape X Strength/Ape_X_StrengthApp.swift`
- Navigation/composition root: `Ape X Strength/Application/RootTabView.swift`
- Dependency graph: `Ape X Strength/Core/DependencyInjection/AppDependencies.swift`
- Repository abstractions/implementations: `Ape X Strength/Core/Repositories/Repositories.swift`
- Core Data setup: `Ape X Strength/Core/Persistence/PersistenceController.swift`
- Core Data schema: `Ape X Strength/Ape_X_Strength.xcdatamodeld/Ape_X_Strength.xcdatamodel/contents`
- Models: `Ape X Strength/Shared/Models/AppModels.swift`
- Settings/sync services: `Ape X Strength/Core/Services/Services.swift`
- Rest-timer coordination: `Ape X Strength/Core/Services/RestTimerCoordinator.swift`
- Design system: `Ape X Strength/Core/DesignSystem/`
- Feature views/view models: `Ape X Strength/Features/`
- Live Activity: `RestTimerWidget/RestTimerWidget.swift`
- Tests: `Ape X StrengthTests/`, `Ape X StrengthUITests/`, and `ManualTest.md`
