import Foundation

protocol SettingsService {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
    var needsSync: Bool { get }
    func markSynced()
    func applyRemote(_ settings: AppSettings)
}

extension SettingsService {
    var needsSync: Bool { false }
    func markSynced() { }
    func applyRemote(_ settings: AppSettings) { save(settings) }
}

final class UserDefaultsSettingsService: SettingsService {
    private enum Key {
        static let weightUnit = "settings.weightUnit"
        static let distanceUnit = "settings.distanceUnit"
        static let restNotifications = "settings.restTimerNotifications"
        static let needsSync = "settings.needsSync"
    }

    private let defaults: UserDefaults
    private let onSave: (() -> Void)?

    init(defaults: UserDefaults = .standard, onSave: (() -> Void)? = nil) {
        self.defaults = defaults
        self.onSave = onSave
    }

    func load() -> AppSettings {
        let storedUnit = defaults.string(forKey: Key.weightUnit)
        let storedDistanceUnit = defaults.string(forKey: Key.distanceUnit)
        return AppSettings(
            weightUnit: WeightUnit(setting: storedUnit ?? "lbs").rawValue,
            distanceUnit: DistanceUnit(setting: storedDistanceUnit ?? "km").rawValue,
            restTimerNotificationsEnabled: defaults.object(forKey: Key.restNotifications) as? Bool ?? true
        )
    }

    func save(_ settings: AppSettings) {
        defaults.set(settings.weightUnit, forKey: Key.weightUnit)
        defaults.set(settings.distanceUnit, forKey: Key.distanceUnit)
        defaults.set(settings.restTimerNotificationsEnabled, forKey: Key.restNotifications)
        defaults.set(true, forKey: Key.needsSync)
        onSave?()
    }

    var needsSync: Bool { defaults.bool(forKey: Key.needsSync) }
    func markSynced() { defaults.set(false, forKey: Key.needsSync) }
    func applyRemote(_ settings: AppSettings) {
        defaults.set(settings.weightUnit, forKey: Key.weightUnit)
        defaults.set(settings.distanceUnit, forKey: Key.distanceUnit)
        defaults.set(settings.restTimerNotificationsEnabled, forKey: Key.restNotifications)
        defaults.set(false, forKey: Key.needsSync)
    }
}

@MainActor
protocol SyncService {
    func hasPendingChanges() throws -> Bool
    func syncIfNeeded() async throws
}

struct NoOpSyncService: SyncService {
    func hasPendingChanges() throws -> Bool { false }
    func syncIfNeeded() async throws { }
}
