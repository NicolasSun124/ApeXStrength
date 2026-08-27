import XCTest
@testable import Ape_X_Strength

final class ModelAndSettingsBusinessLogicTests: XCTestCase {
    func testExerciseConfigurationRoundTripsEverySupportedCombination() {
        for repType in ExerciseRepType.allCases {
            for difficultyType in ExerciseDifficultyType.allCases {
                let original = ExerciseConfiguration(repType: repType, difficultyType: difficultyType)
                let decoded = ExerciseConfiguration(storageValue: original.storageValue)
                XCTAssertEqual(decoded.repType, repType)
                XCTAssertEqual(decoded.difficultyType, difficultyType)
            }
        }
    }

    func testExerciseConfigurationSupportsLegacyAndMalformedValues() {
        let legacy = ExerciseConfiguration(storageValue: "reps_weight")
        XCTAssertEqual(legacy.repType, .reps)
        XCTAssertEqual(legacy.difficultyType, .weighted)

        let bareRepType = ExerciseConfiguration(storageValue: "distance")
        XCTAssertEqual(bareRepType.repType, .distance)
        XCTAssertEqual(bareRepType.difficultyType, .bodyweight)

        let unknown = ExerciseConfiguration(storageValue: "unknown")
        XCTAssertEqual(unknown.repType, .reps)
        XCTAssertEqual(unknown.difficultyType, .bodyweight)
    }

    func testExerciseTitlesDescribeEveryTrackingOption() {
        XCTAssertEqual(ExerciseRepType.allCases.map(\.title), ["Reps", "Time", "Distance"])
        XCTAssertEqual(
            ExerciseDifficultyType.allCases.map(\.title),
            ["Weighted", "Bodyweight", "Assisted Weight"]
        )
    }

    func testTagColorIsCaseInsensitiveForPremadeTagsAndStableForCustomTags() {
        XCTAssertEqual(TagColor(name: "Push"), TagColor(name: "push"))
        XCTAssertEqual(TagColor(name: "My Program"), TagColor(name: "My Program"))
        XCTAssertNotEqual(TagColor(name: "My Program"), TagColor(name: "Another Program"))

        for color in [TagColor(name: "Push"), TagColor(name: "My Program")] {
            XCTAssertTrue((0...1).contains(color.red))
            XCTAssertTrue((0...1).contains(color.green))
            XCTAssertTrue((0...1).contains(color.blue))
        }
    }

    func testUserDefaultsSettingsLifecycleAndRemoteApplication() throws {
        let suiteName = "SettingsTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var saveCallbacks = 0
        let service = UserDefaultsSettingsService(defaults: defaults) { saveCallbacks += 1 }

        XCTAssertEqual(service.load(), AppSettings(
            weightUnit: "lbs", distanceUnit: "km", restTimerNotificationsEnabled: true
        ))
        XCTAssertFalse(service.needsSync)

        let local = AppSettings(weightUnit: "kg", distanceUnit: "mi", restTimerNotificationsEnabled: false)
        service.save(local)
        XCTAssertEqual(service.load(), local)
        XCTAssertTrue(service.needsSync)
        XCTAssertEqual(saveCallbacks, 1)

        service.markSynced()
        XCTAssertFalse(service.needsSync)

        let remote = AppSettings(weightUnit: "lbs", distanceUnit: "km", restTimerNotificationsEnabled: true)
        service.applyRemote(remote)
        XCTAssertEqual(service.load(), remote)
        XCTAssertFalse(service.needsSync)
        XCTAssertEqual(saveCallbacks, 1, "Applying server state must not request another sync")
    }

    func testSettingsNormalizeUnsupportedPersistedUnits() throws {
        let suiteName = "SettingsNormalizationTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("stone", forKey: "settings.weightUnit")
        defaults.set("yards", forKey: "settings.distanceUnit")

        let settings = UserDefaultsSettingsService(defaults: defaults).load()
        XCTAssertEqual(settings.weightUnit, "lbs")
        XCTAssertEqual(settings.distanceUnit, "km")
    }
}
