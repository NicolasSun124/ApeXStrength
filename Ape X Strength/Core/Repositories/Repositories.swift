import CoreData
import Foundation

@MainActor
protocol WorkoutRepository {
    func fetchWorkouts() throws -> [WorkoutListItem]
}

@MainActor
protocol ExerciseRepository {
    func fetchExercises() throws -> [ExerciseListItem]
    func fetchExercise(id: NSManagedObjectID) throws -> ExerciseDetail
    func fetchMuscles() throws -> [MuscleItem]
    @discardableResult func createExercise(_ input: NewExercise) throws -> ExerciseListItem
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
            let configuration = ExerciseConfiguration(storageValue: exercise.trackingType ?? "")
            return ExerciseListItem(
                id: exercise.objectID,
                name: exercise.name ?? "Untitled Exercise",
                repType: configuration.repType,
                difficultyType: configuration.difficultyType,
                targetRestSeconds: Int(exercise.targetRestSeconds)
            )
        }
    }

    func fetchExercise(id: NSManagedObjectID) throws -> ExerciseDetail {
        guard let exercise = try context.existingObject(with: id) as? Exercise,
              !exercise.isDeleted,
              !exercise.isArchived else {
            throw ExerciseRepositoryError.exerciseNotFound
        }

        let configuration = ExerciseConfiguration(storageValue: exercise.trackingType ?? "")
        return ExerciseDetail(
            id: exercise.objectID,
            name: exercise.name ?? "Untitled Exercise",
            repType: configuration.repType,
            difficultyType: configuration.difficultyType,
            targetRestSeconds: Int(exercise.targetRestSeconds),
            primaryMuscle: exercise.primaryMuscle?.name ?? "Not set",
            secondaryMuscles: (exercise.secondaryMuscles as? Set<Muscle> ?? [])
                .compactMap(\.name)
                .sorted()
        )
    }

    func fetchMuscles() throws -> [MuscleItem] {
        let request = Muscle.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        var muscles = try context.fetch(request)

        let existingNames = Set(muscles.compactMap(\.name))
        let missingNames = Self.defaultMuscles.filter { !existingNames.contains($0) }
        if !missingNames.isEmpty {
            let insertedMuscles = missingNames.map { name in
                let muscle = Muscle(context: context)
                muscle.serverID = UUID()
                muscle.name = name
                muscle.colorHex = "8AC5FF"
                return muscle
            }
            muscles.append(contentsOf: insertedMuscles)
            do {
                try context.save()
            } catch {
                insertedMuscles.forEach(context.delete)
                throw error
            }
        }

        return muscles.sorted { ($0.name ?? "") < ($1.name ?? "") }.map {
            MuscleItem(
                id: $0.objectID,
                name: $0.name ?? "Unknown",
                colorHex: $0.colorHex ?? "8AC5FF"
            )
        }
    }

    @discardableResult
    func createExercise(_ input: NewExercise) throws -> ExerciseListItem {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ExerciseRepositoryError.nameRequired }
        guard let primary = try context.existingObject(with: input.primaryMuscleID) as? Muscle else {
            throw ExerciseRepositoryError.primaryMuscleRequired
        }

        let exercise = Exercise(context: context)
        exercise.clientUUID = UUID()
        exercise.createdAt = Date()
        exercise.name = name
        exercise.trackingType = ExerciseConfiguration(
            repType: input.repType,
            difficultyType: input.difficultyType
        ).storageValue
        exercise.targetRestSeconds = Int32(input.targetRestSeconds)
        exercise.primaryMuscle = primary
        exercise.syncState = "pendingCreate"
        exercise.secondaryMuscles = Set(try input.secondaryMuscleIDs.compactMap {
            try context.existingObject(with: $0) as? Muscle
        }) as NSSet
        do {
            try context.save()
        } catch {
            context.delete(exercise)
            throw error
        }

        return ExerciseListItem(
            id: exercise.objectID,
            name: name,
            repType: input.repType,
            difficultyType: input.difficultyType,
            targetRestSeconds: input.targetRestSeconds
        )
    }

    private static let defaultMuscles = [
        "Abdominals",
        "Abductors",
        "Adductors",
        "Biceps",
        "Calves",
        "Forearm Extensors",
        "Forearm Flexors",
        "Front Deltoid",
        "Gluteus maximus",
        "Hamstrings",
        "Lateral Deltoid",
        "Lats",
        "Lower Back",
        "Lower Chest",
        "Lower Traps",
        "Middle Traps",
        "Obliques",
        "Quads",
        "Rear Deltoid",
        "Triceps",
        "Upper Chest",
        "Upper Traps"
    ]
}

enum ExerciseRepositoryError: LocalizedError {
    case exerciseNotFound
    case nameRequired
    case primaryMuscleRequired

    var errorDescription: String? {
        switch self {
        case .exerciseNotFound: "Exercise not found."
        case .nameRequired: "Enter an exercise name."
        case .primaryMuscleRequired: "Select a primary muscle."
        }
    }
}
