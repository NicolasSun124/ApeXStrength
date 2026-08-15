import SwiftUI

@MainActor
final class AppDependencies {
    let persistence: PersistenceController
    let workouts: any WorkoutRepository
    let exercises: any ExerciseRepository
    let settings: any SettingsService
    let sync: any SyncService
    let authentication: any EmailAuthenticationService

    init(
        persistence: PersistenceController,
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        settings: any SettingsService,
        sync: any SyncService,
        authentication: any EmailAuthenticationService
    ) {
        self.persistence = persistence
        self.workouts = workouts
        self.exercises = exercises
        self.settings = settings
        self.sync = sync
        self.authentication = authentication
    }

    static let live: AppDependencies = {
        let persistence = PersistenceController.shared
        let context = persistence.container.viewContext
        let settings = UserDefaultsSettingsService()
        var repositoryUser: User!
        let authentication = TestEmailAuthenticationService { authenticatedUser in
            try persistence.synchronize(authenticatedUser, with: repositoryUser)
        }
        let user: User
        do {
            user = try persistence.initializeUser(authenticatedUser: authentication.authenticatedUser)
            repositoryUser = user
        } catch {
            fatalError("Unable to initialize the temporary user: \(error)")
        }
        return AppDependencies(
            persistence: persistence,
            workouts: CoreDataWorkoutRepository(context: context, settings: settings, user: user),
            exercises: CoreDataExerciseRepository(context: context, user: user),
            settings: settings,
            sync: NoOpSyncService(),
            authentication: authentication
        )
    }()

    static let preview: AppDependencies = {
        let persistence = PersistenceController.preview
        let context = persistence.container.viewContext
        let settings = UserDefaultsSettingsService(defaults: UserDefaults(suiteName: "preview")!)
        let authentication = TestEmailAuthenticationService(
            defaults: UserDefaults(suiteName: "preview-auth")!,
            seededUser: AuthenticatedUser(
                email: "preview@apexstrength.app",
                name: "Preview Athlete",
                isEmailVerified: true
            )
        )
        let user: User
        do {
            user = try persistence.initializeUser(authenticatedUser: authentication.authenticatedUser)
        } catch {
            fatalError("Unable to initialize the preview user: \(error)")
        }
        return AppDependencies(
            persistence: persistence,
            workouts: CoreDataWorkoutRepository(context: context, settings: settings, user: user),
            exercises: CoreDataExerciseRepository(context: context, user: user),
            settings: settings,
            sync: NoOpSyncService(),
            authentication: authentication
        )
    }()

    static let uiTesting: AppDependencies = {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let suite = "ui-testing-\(UUID().uuidString)"
        let settings = UserDefaultsSettingsService(defaults: UserDefaults(suiteName: suite)!)
        let authentication = TestEmailAuthenticationService(
            defaults: UserDefaults(suiteName: suite)!,
            seededUser: AuthenticatedUser(
                email: "ui-test@apexstrength.app",
                name: "UI Test Athlete",
                isEmailVerified: true
            )
        )
        let user = try! persistence.initializeUser(authenticatedUser: authentication.authenticatedUser)

        let muscle = Muscle(context: context)
        muscle.serverID = UUID()
        muscle.name = "Chest"
        muscle.colorHex = "8AC5FF"

        let exercise = Exercise(context: context)
        exercise.clientUUID = UUID()
        exercise.createdAt = Date()
        exercise.name = "Bench Press"
        exercise.syncState = "synced"
        exercise.targetRestSeconds = 1
        exercise.trackingType = ExerciseConfiguration(repType: .reps, difficultyType: .weighted).storageValue
        exercise.owner = user
        exercise.primaryMuscle = muscle

        let workout = WorkoutTemplate(context: context)
        workout.clientUUID = UUID()
        workout.createdAt = Date()
        workout.updatedAt = Date()
        workout.name = "UI Test Workout"
        workout.syncState = "synced"
        workout.user = user

        let occurrence = TemplateExercise(context: context)
        occurrence.clientUUID = UUID()
        occurrence.position = 0
        occurrence.syncState = "synced"
        occurrence.exercise = exercise
        occurrence.workoutTemplate = workout

        let plannedSet = TemplatePlannedSet(context: context)
        plannedSet.clientUUID = UUID()
        plannedSet.setNumber = 1
        plannedSet.plannedReps = 8
        plannedSet.plannedWeight = 100
        plannedSet.syncState = "synced"
        plannedSet.templateExercise = occurrence
        occurrence.plannedSets = NSOrderedSet(object: plannedSet)
        workout.templateExercises = NSOrderedSet(object: occurrence)
        try! context.save()

        return AppDependencies(
            persistence: persistence,
            workouts: CoreDataWorkoutRepository(context: context, settings: settings, user: user),
            exercises: CoreDataExerciseRepository(context: context, user: user),
            settings: settings,
            sync: NoOpSyncService(),
            authentication: authentication
        )
    }()
}

private struct AppDependenciesKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue = AppDependencies.live
}

extension EnvironmentValues {
    var appDependencies: AppDependencies {
        get { self[AppDependenciesKey.self] }
        set { self[AppDependenciesKey.self] = newValue }
    }
}
