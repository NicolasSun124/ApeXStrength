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
        let settings = UserDefaultsSettingsService()
        let user: User
        do {
            user = try persistence.initializeTemporaryUser()
        } catch {
            fatalError("Unable to initialize the temporary user: \(error)")
        }
        return AppDependencies(
            persistence: persistence,
            workouts: CoreDataWorkoutRepository(context: context, settings: settings, user: user),
            exercises: CoreDataExerciseRepository(context: context, user: user),
            settings: settings,
            sync: NoOpSyncService()
        )
    }()

    static let preview: AppDependencies = {
        let persistence = PersistenceController.preview
        let context = persistence.container.viewContext
        let settings = UserDefaultsSettingsService(defaults: UserDefaults(suiteName: "preview")!)
        let user: User
        do {
            user = try persistence.initializeTemporaryUser()
        } catch {
            fatalError("Unable to initialize the preview user: \(error)")
        }
        return AppDependencies(
            persistence: persistence,
            workouts: CoreDataWorkoutRepository(context: context, settings: settings, user: user),
            exercises: CoreDataExerciseRepository(context: context, user: user),
            settings: settings,
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
