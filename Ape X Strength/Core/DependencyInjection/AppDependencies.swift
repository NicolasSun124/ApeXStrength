import SwiftUI

@MainActor
final class AppDependencies {
    let persistence: PersistenceController
    let workouts: any WorkoutRepository
    let exercises: any ExerciseRepository
    let settings: any SettingsService
    let sync: any SyncService

    init(
        persistence: PersistenceController,
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        settings: any SettingsService,
        sync: any SyncService
    ) {
        self.persistence = persistence
        self.workouts = workouts
        self.exercises = exercises
        self.settings = settings
        self.sync = sync
    }

    static let live: AppDependencies = {
        let persistence = PersistenceController.shared
        let context = persistence.container.viewContext
        return AppDependencies(
            persistence: persistence,
            workouts: CoreDataWorkoutRepository(context: context),
            exercises: CoreDataExerciseRepository(context: context),
            settings: UserDefaultsSettingsService(),
            sync: NoOpSyncService()
        )
    }()

    static let preview: AppDependencies = {
        let persistence = PersistenceController.preview
        let context = persistence.container.viewContext
        return AppDependencies(
            persistence: persistence,
            workouts: CoreDataWorkoutRepository(context: context),
            exercises: CoreDataExerciseRepository(context: context),
            settings: UserDefaultsSettingsService(defaults: UserDefaults(suiteName: "preview")!),
            sync: NoOpSyncService()
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
