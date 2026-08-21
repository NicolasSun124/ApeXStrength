import CoreData
import XCTest
@testable import Ape_X_Strength

final class RepositoryPersistenceTests: XCTestCase {
    @MainActor
    func testRepositoryCreateFetchArchiveRestoreAndOrdering() throws {
        let fixture = try RepositoryFixture()
        let first = try fixture.makeExercise(name: "Bench")
        let second = try fixture.makeExercise(name: "Fly")
        let workout = try fixture.makeWorkout(exercises: [first, second])

        XCTAssertEqual(try fixture.workouts.fetchWorkouts().map(\.name), ["Push"])
        XCTAssertEqual(try fixture.workouts.fetchWorkoutPreview(id: workout.objectID).exercises.map(\.name), ["Bench", "Fly"])

        try fixture.workouts.reorderExercises([second.objectID, first.objectID], inWorkout: workout.objectID)
        XCTAssertEqual(try fixture.workouts.fetchWorkoutPreview(id: workout.objectID).exercises.map(\.name), ["Fly", "Bench"])

        try fixture.workouts.archiveWorkout(id: workout.objectID)
        XCTAssertTrue(try fixture.workouts.fetchWorkouts().isEmpty)
        XCTAssertEqual(try fixture.workouts.fetchArchivedWorkouts().map(\.name), ["Push"])
        try fixture.workouts.restoreWorkout(id: workout.objectID)
        XCTAssertEqual(try fixture.workouts.fetchWorkouts().count, 1)
    }

    @MainActor
    func testExerciseRepositoryRoundTripAndArchive() throws {
        let fixture = try RepositoryFixture()
        let created = try fixture.exercises.createExercise(NewExercise(
            name: "Incline Press",
            repType: .reps,
            difficultyType: .weighted,
            targetRestSeconds: 90,
            primaryMuscleID: fixture.muscle.objectID,
            secondaryMuscleIDs: []
        ))
        let detail = try fixture.exercises.fetchExercise(id: created.id)
        XCTAssertEqual(detail.name, "Incline Press")
        XCTAssertEqual(detail.targetRestSeconds, 90)
        XCTAssertEqual(detail.primaryMuscle.name, "Chest")

        try fixture.exercises.archiveExercise(id: created.id)
        XCTAssertFalse(try fixture.exercises.fetchArchivedExercises().isEmpty)
        try fixture.exercises.restoreExercise(id: created.id)
        XCTAssertTrue(try fixture.exercises.fetchArchivedExercises().isEmpty)
    }

    @MainActor
    func testActiveSessionPersistsUpdatesAndCanBeDiscarded() throws {
        let fixture = try RepositoryFixture()
        let exercise = try fixture.makeExercise()
        let workout = try fixture.makeWorkout(exercises: [exercise])
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let id = try fixture.workouts.startSession(
            workoutID: workout.objectID,
            startedAt: started,
            exercises: [fixture.input(exercise, reps: 8, completed: false)]
        )
        try fixture.workouts.updateActiveSession(id: id, exercises: [fixture.input(exercise, reps: 10)])

        fixture.context.reset()
        let draft = try XCTUnwrap(fixture.workouts.fetchActiveSessionDraft())
        XCTAssertEqual(draft.id, id)
        XCTAssertEqual(draft.startedAt, started)
        XCTAssertEqual(draft.workout.exercises.first?.sets.first?.reps, 10)
        XCTAssertEqual(draft.completedSetNumbersByExerciseID[exercise.objectID], [1])

        try fixture.workouts.discardSession(id: id)
        XCTAssertNil(try fixture.workouts.fetchActiveSessionDraft())
    }

    @MainActor
    func testStartingASecondActiveSessionIsRejected() throws {
        let fixture = try RepositoryFixture()
        let exercise = try fixture.makeExercise()
        let workout = try fixture.makeWorkout(exercises: [exercise])
        let first = try fixture.workouts.startSession(
            workoutID: workout.objectID,
            startedAt: Date(timeIntervalSince1970: 100),
            exercises: [fixture.input(exercise, reps: 1)]
        )
        XCTAssertThrowsError(try fixture.workouts.startSession(
            workoutID: workout.objectID,
            startedAt: Date(timeIntervalSince1970: 200),
            exercises: [fixture.input(exercise, reps: 2)]
        )) { error in
            guard case WorkoutRepositoryError.activeSessionAlreadyExists = error else {
                return XCTFail("Expected activeSessionAlreadyExists, got \(error)")
            }
        }
        XCTAssertEqual(try fixture.workouts.fetchActiveSessionDraft()?.id, first)
    }

    @MainActor
    func testSetCompletionTimestampSurvivesAutosaveAndFinish() throws {
        let fixture = try RepositoryFixture()
        let exercise = try fixture.makeExercise()
        let workout = try fixture.makeWorkout(exercises: [exercise])
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let completed = started.addingTimeInterval(125)
        let input = CompletedSessionExercise(exerciseID: exercise.objectID, sets: [CompletedSessionSet(
            number: 1, reps: 8, timeSeconds: 0, distance: 0, weight: 100,
            completed: true, completedAt: completed
        )])
        let id = try fixture.workouts.startSession(
            workoutID: workout.objectID, startedAt: started,
            exercises: [fixture.input(exercise, completed: false)]
        )

        try fixture.workouts.updateActiveSession(id: id, exercises: [input])
        XCTAssertEqual(try fixture.workouts.fetchActiveSessionDraft()?
            .completedAtByExerciseIDAndSetNumber[exercise.objectID]?[1], completed)

        let ended = started.addingTimeInterval(600)
        try fixture.workouts.saveCompletedSession(CompletedWorkoutSession(
            id: id, workoutID: workout.objectID, startedAt: started, endedAt: ended,
            rating: 4, note: nil, exercises: [input]
        ))
        let session = try XCTUnwrap(fixture.context.existingObject(with: id) as? WorkoutSession)
        let occurrence = try XCTUnwrap(session.sessionExercises?.firstObject as? SessionExercise)
        let savedSet = try XCTUnwrap(occurrence.sets?.firstObject as? SessionSet)
        XCTAssertEqual(savedSet.completedAt, completed)
        XCTAssertNotEqual(savedSet.completedAt, ended)
    }

    @MainActor
    func testHidingGlobalExerciseOnlyAffectsCurrentUser() throws {
        let fixture = try RepositoryFixture()
        let otherUser = User(context: fixture.context)
        otherUser.serverID = UUID()
        otherUser.email = "other@example.com"
        let global = Exercise(context: fixture.context)
        global.name = "Global Squat"
        global.serverID = UUID()
        global.createdAt = Date()
        global.trackingType = "reps|weighted"
        global.primaryMuscle = fixture.muscle
        try fixture.context.save()
        let otherRepository = CoreDataExerciseRepository(context: fixture.context, user: otherUser)

        try fixture.exercises.archiveExercise(id: global.objectID)

        XCTAssertEqual(fixture.user.hiddenExercisesSyncState, "pendingUpdate")
        XCTAssertFalse(try fixture.exercises.fetchExercises().contains { $0.id == global.objectID })
        XCTAssertTrue(try fixture.exercises.fetchArchivedExercises().contains { $0.id == global.objectID })
        XCTAssertTrue(try otherRepository.fetchExercises().contains { $0.id == global.objectID })

        fixture.user.hiddenExercisesSyncState = "synced"
        try fixture.exercises.restoreExercise(id: global.objectID)
        XCTAssertEqual(fixture.user.hiddenExercisesSyncState, "pendingUpdate")
    }

    @MainActor
    func testDuplicateExerciseOccurrencesRemainDistinctAndOrdered() throws {
        let fixture = try RepositoryFixture()
        let exercise = try fixture.makeExercise()
        let workout = try fixture.makeWorkout(exercises: [exercise])
        let inputs = [fixture.input(exercise, reps: 5), fixture.input(exercise, reps: 12)]
        let id = try fixture.workouts.startSession(workoutID: workout.objectID, startedAt: Date(), exercises: inputs)

        let session = try XCTUnwrap(fixture.context.existingObject(with: id) as? WorkoutSession)
        let occurrences = try XCTUnwrap(session.sessionExercises?.array as? [SessionExercise])
        XCTAssertEqual(occurrences.count, 2)
        XCTAssertNotEqual(occurrences[0].objectID, occurrences[1].objectID)
        XCTAssertEqual(occurrences.map(\.position), [0, 1])
        XCTAssertEqual(occurrences.compactMap { ($0.sets?.firstObject as? SessionSet)?.reps }, [5, 12])

        let draft = try XCTUnwrap(fixture.workouts.fetchActiveSessionDraft())
        XCTAssertEqual(draft.workout.exercises.count, 2)
        XCTAssertEqual(draft.workout.exercises.compactMap { $0.sets.first?.reps }, [5, 12])
    }
}
