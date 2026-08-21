import XCTest
@testable import Ape_X_Strength

final class CalculationsAndEdgeCaseTests: XCTestCase {
    @MainActor
    func testUnauthorizedSyncInvalidatesSessionAndRestoresPendingData() async throws {
        let fixture = try RepositoryFixture()
        fixture.user.syncProtocolVersion = 2
        fixture.user.hiddenExercisesSyncState = "synced"
        let exercise = try fixture.makeExercise()
        exercise.syncState = "pendingCreate"
        try fixture.context.save()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UnauthorizedURLProtocol.self]
        let session = URLSession(configuration: configuration)
        var didInvalidateSession = false
        let service = APISyncService(
            context: fixture.context,
            userProvider: { fixture.user },
            settings: fixture.settings,
            baseURL: URL(string: "https://example.test/v1")!,
            session: session,
            token: { "expired-token" },
            onUnauthorized: { didInvalidateSession = true }
        )

        do {
            try await service.syncIfNeeded()
            XCTFail("Expected an unauthorized sync error")
        } catch SyncServiceError.unauthorized {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(didInvalidateSession)
        XCTAssertEqual(exercise.syncState, "pendingUpdate")
        XCTAssertTrue(try service.hasPendingChanges())
    }

    @MainActor
    func testStatisticsAverageCompletedSessionsAndIgnoreUnavailableValues() throws {
        let fixture = try RepositoryFixture()
        let exercise = try fixture.makeExercise()
        let workout = try fixture.makeWorkout(exercises: [exercise])
        let dayOne = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try fixture.finish(
            workout: workout,
            inputs: [fixture.input(exercise, reps: 10, weight: 100)],
            start: dayOne,
            end: dayOne.addingTimeInterval(1_800)
        )
        first.averageRestSeconds = 60
        first.estimatedIntensity = 7
        let dayTwo = dayOne.addingTimeInterval(86_400)
        let second = try fixture.finish(
            workout: workout,
            inputs: [fixture.input(exercise, reps: 5, weight: 200)],
            start: dayTwo,
            end: dayTwo.addingTimeInterval(3_600)
        )
        second.averageRestSeconds = 120
        second.estimatedIntensity = 9
        try fixture.context.save()

        let statistics = try XCTUnwrap(fixture.workouts.fetchWorkouts().first?.statistics)
        XCTAssertEqual(statistics.lastUsed, dayTwo.addingTimeInterval(3_600))
        XCTAssertEqual(try XCTUnwrap(statistics.meanDurationMinutes), 45, accuracy: 0.001)
        XCTAssertDecimalEqual(statistics.meanVolume, 1_000)
        XCTAssertEqual(try XCTUnwrap(statistics.meanRestSeconds), 90, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(statistics.meanIntensity), 8, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(statistics.meanPercentCompleted), 100, accuracy: 0.001)
    }

    @MainActor
    func testImprovementComparisonAgainstPreviousAndLifetimeBest() throws {
        let fixture = try RepositoryFixture()
        let exercise = try fixture.makeExercise()
        let workout = try fixture.makeWorkout(exercises: [exercise])
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try fixture.finish(
            workout: workout,
            inputs: [fixture.input(exercise, reps: 8, weight: 100)],
            start: base,
            end: base.addingTimeInterval(60)
        )
        _ = try fixture.finish(
            workout: workout,
            inputs: [fixture.input(exercise, reps: 10, weight: 100)],
            start: base.addingTimeInterval(100),
            end: base.addingTimeInterval(160)
        )

        let result = try XCTUnwrap(fixture.workouts.calculateImprovements(
            for: [fixture.input(exercise, reps: 12, weight: 100)]
        ).first)
        XCTAssertEqual(result.previous.metrics.map(\.title), ["Max Reps", "Max Weight", "Volume Weight"])
        XCTAssertEqual(result.previous.metrics.first?.displayValue, "10 → 12 @ 100 lbs")
        assertTrend(result.previous.metrics.first?.trend, is: .improved)
        assertTrend(result.lifetime.metrics.first?.trend, is: .improved)
    }

    @MainActor
    func testAssistanceImprovesWhenRequiredWeightDecreases() throws {
        let fixture = try RepositoryFixture()
        let exercise = try fixture.makeExercise(difficulty: .assistedWeight)
        let workout = try fixture.makeWorkout(exercises: [exercise])
        let date = Date(timeIntervalSince1970: 10_000)
        _ = try fixture.finish(
            workout: workout,
            inputs: [fixture.input(exercise, reps: 8, weight: 50)],
            start: date,
            end: date.addingTimeInterval(60)
        )
        let metrics = try XCTUnwrap(fixture.workouts.calculateImprovements(
            for: [fixture.input(exercise, reps: 8, weight: 40)]
        ).first?.previous.metrics)
        XCTAssertEqual(metrics.map(\.title), ["Max Reps", "Min Assistance"])
        assertTrend(metrics[1].trend, is: .improved)
    }

    func testWeightConversionKnownValuesFallbackAndRoundTrip() {
        XCTAssertEqual(WeightUnit(setting: "unexpected").rawValue, "lbs")
        XCTAssertDecimalEqual(WeightUnit.kilograms.displayed(fromPounds: Decimal(string: "220.46226218")!), 100)
        for value in [Decimal.zero, 1, Decimal(string: "123.456")!] {
            let pounds = WeightUnit.kilograms.pounds(fromDisplayed: value)
            XCTAssertDecimalEqual(WeightUnit.kilograms.displayed(fromPounds: pounds), value, accuracy: 0.000001)
        }
        XCTAssertEqual(DistanceUnit(setting: "mi"), .miles)
        XCTAssertEqual(DistanceUnit(setting: "invalid"), .kilometers)
    }

    func testTimerFormattingHandlesMinuteAndHourBoundaries() {
        XCTAssertEqual(ActiveWorkoutView.timerText(seconds: 0), "00:00")
        XCTAssertEqual(ActiveWorkoutView.timerText(seconds: 59), "00:59")
        XCTAssertEqual(ActiveWorkoutView.timerText(seconds: 60), "01:00")
        XCTAssertEqual(ActiveWorkoutView.timerText(seconds: 3_661), "61:01")
    }

    func testRestTimerRecoveryIsSessionScopedAndClearsExpiredState() throws {
        let suiteName = "RestTimerTests-\(UUID())"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 1_000)
        let end = now.addingTimeInterval(90)
        suite.set(end, forKey: "restTimer.endDate")
        suite.set("session-a", forKey: "restTimer.sessionIdentifier")
        XCTAssertEqual(RestTimerCoordinator.restoredEndDate(for: "session-a", defaults: suite, now: now), end)
        XCTAssertNil(RestTimerCoordinator.restoredEndDate(for: "session-b", defaults: suite, now: now))
        XCTAssertNil(suite.object(forKey: "restTimer.endDate"))

        suite.set(now, forKey: "restTimer.endDate")
        suite.set("session-a", forKey: "restTimer.sessionIdentifier")
        XCTAssertNil(RestTimerCoordinator.restoredEndDate(for: "session-a", defaults: suite, now: now))
    }

    @MainActor
    func testBackgroundSaveAndRepeatedInterruptionKeepsLatestDraft() throws {
        let fixture = try RepositoryFixture()
        let exercise = try fixture.makeExercise()
        let workout = try fixture.makeWorkout(exercises: [exercise])
        let id = try fixture.workouts.startSession(
            workoutID: workout.objectID,
            startedAt: Date(),
            exercises: [fixture.input(exercise, reps: 1, completed: false)]
        )
        try fixture.workouts.updateActiveSession(id: id, exercises: [fixture.input(exercise, reps: 6)])
        fixture.context.reset() // Equivalent to losing all in-memory view state while backgrounded.
        try fixture.workouts.updateActiveSession(id: id, exercises: [fixture.input(exercise, reps: 9)])
        fixture.context.reset()

        let recovered = try XCTUnwrap(fixture.workouts.fetchActiveSessionDraft())
        XCTAssertEqual(recovered.workout.exercises.first?.sets.first?.reps, 9)
        XCTAssertEqual(recovered.completedSetNumbersByExerciseID[exercise.objectID], [1])
    }

    @MainActor
    func testDSTAndTimeZoneDoNotChangeAbsoluteDurationOrOrdering() throws {
        let fixture = try RepositoryFixture()
        let exercise = try fixture.makeExercise()
        let workout = try fixture.makeWorkout(exercises: [exercise])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 30)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 30)))
        let session = try fixture.finish(workout: workout, inputs: [fixture.input(exercise)], start: start, end: end)
        XCTAssertEqual(session.durationSeconds, 3_600, "Spring-forward skips one wall-clock hour")

        let history = try fixture.workouts.fetchSessionHistory()
        XCTAssertEqual(history.first?.startedAt, start)
        XCTAssertEqual(history.first?.endedAt, end)
        XCTAssertEqual(history.first?.durationSeconds, 3_600)
    }

    private func assertTrend(
        _ actual: ImprovementTrend?,
        is expected: ImprovementTrend,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else { return XCTFail("Missing trend", file: file, line: line) }
        switch (actual, expected) {
        case (.improved, .improved), (.maintained, .maintained), (.regressed, .regressed), (.firstEntry, .firstEntry): break
        default: XCTFail("Unexpected trend", file: file, line: line)
        }
    }

}

private final class UnauthorizedURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"error":"Unauthorized"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }
}
