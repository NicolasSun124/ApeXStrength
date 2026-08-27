import CoreData
import XCTest
@testable import Ape_X_Strength

final class RepositoryBusinessLogicTests: XCTestCase {
    @MainActor
    func testWorkoutCreationTrimsNameConvertsKilogramsAndRequestsSync() throws {
        let fixture = try RepositoryFixture(weightUnit: "kg")
        let exercise = try fixture.makeExercise()
        var syncRequests = 0
        let repository = CoreDataWorkoutRepository(
            context: fixture.context, settings: fixture.settings, user: fixture.user,
            onSyncRequested: { syncRequests += 1 }
        )

        let created = try repository.createWorkout(NewWorkout(
            name: "  Heavy Day  ", exerciseIDs: [exercise.objectID], selectedTagIDs: [],
            plannedSetsByExerciseID: [exercise.objectID: [NewPlannedSet(
                reps: 5, timeSeconds: nil, distance: nil, weight: 100
            )]], alternateExerciseIDsByExerciseID: [:]
        ))

        XCTAssertEqual(created.name, "Heavy Day")
        XCTAssertEqual(syncRequests, 1)
        let workout = try XCTUnwrap(fixture.context.existingObject(with: created.id) as? WorkoutTemplate)
        XCTAssertEqual(workout.syncState, "pendingCreate")
        let item = try XCTUnwrap(workout.templateExercises?.firstObject as? TemplateExercise)
        let set = try XCTUnwrap(item.plannedSets?.firstObject as? TemplatePlannedSet)
        XCTAssertDecimalEqual(set.plannedWeight as Decimal?, Decimal(string: "220.46226218")!)
    }

    @MainActor
    func testWorkoutAndTagValidationRejectInvalidInputAndDeduplicatesTags() throws {
        let fixture = try RepositoryFixture()
        let exercise = try fixture.makeExercise()
        XCTAssertThrowsError(try fixture.workouts.createWorkout(NewWorkout(
            name: "   ", exerciseIDs: [exercise.objectID], selectedTagIDs: [],
            plannedSetsByExerciseID: [:], alternateExerciseIDsByExerciseID: [:]
        ))) { XCTAssertWorkoutError($0, is: .nameRequired) }
        XCTAssertThrowsError(try fixture.workouts.createWorkout(NewWorkout(
            name: "Empty", exerciseIDs: [], selectedTagIDs: [],
            plannedSetsByExerciseID: [:], alternateExerciseIDsByExerciseID: [:]
        ))) { XCTAssertWorkoutError($0, is: .exerciseRequired) }
        XCTAssertThrowsError(try fixture.workouts.createTag(named: " \n ")) {
            XCTAssertWorkoutError($0, is: .tagNameRequired)
        }

        let first = try fixture.workouts.createTag(named: "  Strength ")
        let duplicate = try fixture.workouts.createTag(named: "strength")
        XCTAssertEqual(first.id, duplicate.id)
        XCTAssertEqual(first.name, "Strength")
    }

    @MainActor
    func testWorkoutMutationsMaintainAlternatesSetsOrderingAndSyncState() throws {
        let fixture = try RepositoryFixture()
        let bench = try fixture.makeExercise(name: "Bench")
        let fly = try fixture.makeExercise(name: "Fly")
        let row = try fixture.makeExercise(name: "Row")
        let workout = try fixture.makeWorkout(exercises: [bench, fly], setCount: 3)

        try fixture.workouts.setAlternateExercises([row.objectID], forExercise: bench.objectID, inWorkout: workout.objectID)
        XCTAssertEqual(try fixture.workouts.fetchWorkoutPreview(id: workout.objectID).exercises[0].alternates.map(\.name), ["Row"])

        try fixture.workouts.replaceExercise(bench.objectID, with: row.objectID, inWorkout: workout.objectID)
        let replaced = try fixture.workouts.fetchWorkoutPreview(id: workout.objectID)
        XCTAssertEqual(replaced.exercises.map(\.name), ["Row", "Fly"])
        XCTAssertEqual(replaced.exercises[0].alternates.map(\.name), ["Bench"])

        try fixture.workouts.removePlannedSet(number: 2, fromExercise: row.objectID, inWorkout: workout.objectID)
        XCTAssertEqual(try fixture.workouts.fetchWorkoutPreview(id: workout.objectID).exercises[0].sets.map(\.number), [1, 2])
        XCTAssertEqual(workout.syncState, "pendingUpdate")
    }

    @MainActor
    func testSessionCalculatesOnlyCompletedSetVolumeAndCompletionPercentage() throws {
        let fixture = try RepositoryFixture(weightUnit: "kg")
        let exercise = try fixture.makeExercise()
        let workout = try fixture.makeWorkout(exercises: [exercise])
        let sets = [
            CompletedSessionSet(number: 1, reps: 10, timeSeconds: 0, distance: 0, weight: 10, completed: true),
            CompletedSessionSet(number: 2, reps: 20, timeSeconds: 0, distance: 0, weight: 50, completed: false)
        ]
        let id = try fixture.workouts.startSession(
            workoutID: workout.objectID, startedAt: Date(),
            exercises: [CompletedSessionExercise(exerciseID: exercise.objectID, sets: sets)]
        )
        let session = try XCTUnwrap(fixture.context.existingObject(with: id) as? WorkoutSession)

        XCTAssertEqual(session.percentCompleted, 50, accuracy: 0.001)
        XCTAssertDecimalEqual(session.volumeWeight as Decimal?, Decimal(string: "220.46226218")!)
    }

    @MainActor
    func testImprovementMetricsCoverFirstEntryMaintainedRegressionAndUncompletedInput() throws {
        let fixture = try RepositoryFixture()
        let exercise = try fixture.makeExercise(difficulty: .bodyweight)
        let workout = try fixture.makeWorkout(exercises: [exercise])

        let first = try XCTUnwrap(fixture.workouts.calculateImprovements(
            for: [fixture.input(exercise, reps: 8)]
        ).first?.previous.metrics.first)
        assertTrend(first.trend, is: .firstEntry)
        XCTAssertEqual(first.displayValue, "8")

        _ = try fixture.finish(
            workout: workout, inputs: [fixture.input(exercise, reps: 8)],
            start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 200)
        )
        assertTrend(try metric(fixture, exercise, reps: 8).trend, is: .maintained)
        assertTrend(try metric(fixture, exercise, reps: 6).trend, is: .regressed)

        let incomplete = try XCTUnwrap(fixture.workouts.calculateImprovements(
            for: [fixture.input(exercise, reps: 20, completed: false)]
        ).first?.previous.metrics.first)
        XCTAssertEqual(incomplete.displayValue, "–")
        assertTrend(incomplete.trend, is: .firstEntry)
    }

    @MainActor
    private func metric(_ fixture: RepositoryFixture, _ exercise: Exercise, reps: Int) throws -> ImprovementMetric {
        try XCTUnwrap(fixture.workouts.calculateImprovements(
            for: [fixture.input(exercise, reps: reps)]
        ).first?.previous.metrics.first)
    }

    private func assertTrend(_ actual: ImprovementTrend, is expected: ImprovementTrend, file: StaticString = #filePath, line: UInt = #line) {
        switch (actual, expected) {
        case (.improved, .improved), (.maintained, .maintained), (.regressed, .regressed), (.firstEntry, .firstEntry): break
        default: XCTFail("Unexpected trend", file: file, line: line)
        }
    }
}

private func XCTAssertWorkoutError(
    _ actual: Error, is expected: WorkoutRepositoryError,
    file: StaticString = #filePath, line: UInt = #line
) {
    guard let actual = actual as? WorkoutRepositoryError else {
        return XCTFail("Unexpected error: \(actual)", file: file, line: line)
    }
    XCTAssertEqual(actual.errorDescription, expected.errorDescription, file: file, line: line)
}
