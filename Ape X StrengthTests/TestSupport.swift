import CoreData
import XCTest
@testable import Ape_X_Strength

final class TestSettingsService: SettingsService {
    var value: AppSettings

    init(weightUnit: String = "lbs", distanceUnit: String = "km", notifications: Bool = false) {
        value = AppSettings(
            weightUnit: weightUnit,
            distanceUnit: distanceUnit,
            restTimerNotificationsEnabled: notifications
        )
    }

    func load() -> AppSettings { value }
    func save(_ settings: AppSettings) { value = settings }
}

@MainActor
struct RepositoryFixture {
    let persistence: PersistenceController
    let context: NSManagedObjectContext
    let user: User
    let muscle: Muscle
    let settings: TestSettingsService
    let workouts: CoreDataWorkoutRepository
    let exercises: CoreDataExerciseRepository

    init(weightUnit: String = "lbs") throws {
        persistence = PersistenceController(inMemory: true)
        context = persistence.container.viewContext
        user = try persistence.initializeTemporaryUser()
        settings = TestSettingsService(weightUnit: weightUnit)

        muscle = Muscle(context: context)
        muscle.serverID = UUID()
        muscle.name = "Chest"
        muscle.colorHex = "112233"
        try context.save()

        workouts = CoreDataWorkoutRepository(context: context, settings: settings, user: user)
        exercises = CoreDataExerciseRepository(context: context, user: user)
    }

    func makeExercise(
        name: String = "Bench Press",
        repType: ExerciseRepType = .reps,
        difficulty: ExerciseDifficultyType = .weighted,
        rest: Int32 = 120
    ) throws -> Exercise {
        let exercise = Exercise(context: context)
        exercise.clientUUID = UUID()
        exercise.createdAt = Date()
        exercise.name = name
        exercise.syncState = "synced"
        exercise.targetRestSeconds = rest
        exercise.trackingType = ExerciseConfiguration(repType: repType, difficultyType: difficulty).storageValue
        exercise.owner = user
        exercise.primaryMuscle = muscle
        try context.save()
        return exercise
    }

    func makeWorkout(name: String = "Push", exercises: [Exercise], setCount: Int = 2) throws -> WorkoutTemplate {
        let workout = WorkoutTemplate(context: context)
        workout.clientUUID = UUID()
        workout.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        workout.updatedAt = workout.createdAt
        workout.name = name
        workout.syncState = "synced"
        workout.user = user

        let items = exercises.enumerated().map { position, exercise in
            let item = TemplateExercise(context: context)
            item.clientUUID = UUID()
            item.position = Int32(position)
            item.syncState = "synced"
            item.exercise = exercise
            item.workoutTemplate = workout
            item.plannedSets = NSOrderedSet(array: (1...setCount).map { number in
                let set = TemplatePlannedSet(context: context)
                set.clientUUID = UUID()
                set.setNumber = Int32(number)
                set.plannedReps = 8
                set.plannedWeight = 100
                set.syncState = "synced"
                set.templateExercise = item
                return set
            })
            return item
        }
        workout.templateExercises = NSOrderedSet(array: items)
        try context.save()
        return workout
    }

    func input(_ exercise: Exercise, reps: Int = 8, weight: Decimal = 100, completed: Bool = true) -> CompletedSessionExercise {
        CompletedSessionExercise(
            exerciseID: exercise.objectID,
            sets: [CompletedSessionSet(
                number: 1,
                reps: reps,
                timeSeconds: 0,
                distance: 0,
                weight: weight,
                completed: completed
            )]
        )
    }

    func finish(
        workout: WorkoutTemplate,
        inputs: [CompletedSessionExercise],
        start: Date,
        end: Date,
        rating: Int = 4
    ) throws -> WorkoutSession {
        let id = try workouts.startSession(workoutID: workout.objectID, startedAt: start, exercises: inputs)
        try workouts.saveCompletedSession(CompletedWorkoutSession(
            id: id,
            workoutID: workout.objectID,
            startedAt: start,
            endedAt: end,
            rating: rating,
            note: "fixture",
            exercises: inputs
        ))
        return try XCTUnwrap(context.existingObject(with: id) as? WorkoutSession)
    }
}

func XCTAssertDecimalEqual(
    _ actual: Decimal?,
    _ expected: Decimal,
    accuracy: Double = 0.0001,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let actual else {
        return XCTFail("Expected decimal \(expected), got nil", file: file, line: line)
    }
    XCTAssertEqual(
        NSDecimalNumber(decimal: actual).doubleValue,
        NSDecimalNumber(decimal: expected).doubleValue,
        accuracy: accuracy,
        file: file,
        line: line
    )
}
