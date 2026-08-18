import CoreData
import XCTest
@testable import Ape_X_Strength

final class MigrationAndPerformanceTests: XCTestCase {
    @MainActor
    func testPersistentStoreReopensWithMigrationOptionsAndPreservesData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigrationTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Ape_X_Strength.sqlite")

        autoreleasepool {
            let first = PersistenceController(storeURL: url)
            let description = first.container.persistentStoreDescriptions[0]
            XCTAssertEqual(description.shouldMigrateStoreAutomatically, true)
            XCTAssertEqual(description.shouldInferMappingModelAutomatically, true)
            let user = try! first.initializeTemporaryUser()
            let workout = WorkoutTemplate(context: first.container.viewContext)
            workout.clientUUID = UUID()
            workout.createdAt = Date(timeIntervalSince1970: 123)
            workout.updatedAt = Date(timeIntervalSince1970: 456)
            workout.name = "Migration Sentinel"
            workout.syncState = "synced"
            workout.user = user
            try! first.container.viewContext.save()
        }

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: url,
            options: nil
        )
        let reopened = PersistenceController(storeURL: url)
        XCTAssertTrue(reopened.container.managedObjectModel.isConfiguration(
            withName: nil,
            compatibleWithStoreMetadata: metadata
        ))
        let request = WorkoutTemplate.fetchRequest()
        request.predicate = NSPredicate(format: "name == %@", "Migration Sentinel")
        XCTAssertEqual(try reopened.container.viewContext.count(for: request), 1)
        try reopened.container.persistentStoreCoordinator.destroyPersistentStore(
            at: url,
            type: .sqlite,
            options: nil
        )
    }

    @MainActor
    func testLargeHistoryFetchPerformanceAndDescendingOrder() throws {
        let fixture = try RepositoryFixture()
        let exercise = try fixture.makeExercise()
        let workout = try fixture.makeWorkout(exercises: [exercise], setCount: 1)
        let base = Date(timeIntervalSince1970: 1_600_000_000)

        for index in 0..<2_000 {
            let session = WorkoutSession(context: fixture.context)
            session.clientUUID = UUID()
            session.startedAt = base.addingTimeInterval(Double(index * 3_600))
            session.endedAt = session.startedAt?.addingTimeInterval(1_800)
            session.durationSeconds = 1_800
            session.percentCompleted = 100
            session.volumeWeight = 1_000
            session.rating = 4
            session.syncState = "synced"
            session.user = fixture.user
            session.workoutTemplate = workout
        }
        try fixture.context.save()

        var history: [WorkoutSessionHistoryItem] = []
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            history = try! fixture.workouts.fetchSessionHistory()
        }
        XCTAssertEqual(history.count, 2_000)
        XCTAssertGreaterThan(try XCTUnwrap(history.first?.endedAt), try XCTUnwrap(history.last?.endedAt))
    }
}
