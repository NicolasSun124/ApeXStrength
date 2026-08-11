import CoreData
import Foundation

@MainActor
protocol WorkoutRepository {
    func fetchWorkouts() throws -> [WorkoutListItem]
}

@MainActor
protocol ExerciseRepository {
    func fetchExercises() throws -> [ExerciseListItem]
}

@MainActor
final class CoreDataWorkoutRepository: WorkoutRepository {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func fetchWorkouts() throws -> [WorkoutListItem] {
        let request = WorkoutTemplate.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        request.predicate = NSPredicate(format: "isArchived == NO")

        return try context.fetch(request).map { workout in
            WorkoutListItem(
                id: workout.objectID,
                name: workout.name ?? "Untitled Workout",
                exerciseCount: workout.templateExercises?.count ?? 0,
                updatedAt: workout.updatedAt ?? .distantPast
            )
        }
    }
}

@MainActor
final class CoreDataExerciseRepository: ExerciseRepository {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func fetchExercises() throws -> [ExerciseListItem] {
        let request = Exercise.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        request.predicate = NSPredicate(format: "isArchived == NO")

        return try context.fetch(request).map { exercise in
            ExerciseListItem(
                id: exercise.objectID,
                name: exercise.name ?? "Untitled Exercise",
                trackingType: exercise.trackingType ?? "reps_weight",
                targetRestSeconds: Int(exercise.targetRestSeconds)
            )
        }
    }
}
