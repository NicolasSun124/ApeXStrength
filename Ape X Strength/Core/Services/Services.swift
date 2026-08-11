import Foundation

protocol SettingsService {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

final class UserDefaultsSettingsService: SettingsService {
    private enum Key {
        static let weightUnit = "settings.weightUnit"
        static let restNotifications = "settings.restTimerNotifications"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        AppSettings(
            weightUnit: defaults.string(forKey: Key.weightUnit) ?? "kg",
            restTimerNotificationsEnabled: defaults.object(forKey: Key.restNotifications) as? Bool ?? true
        )
    }

    func save(_ settings: AppSettings) {
        defaults.set(settings.weightUnit, forKey: Key.weightUnit)
        defaults.set(settings.restTimerNotificationsEnabled, forKey: Key.restNotifications)
    }
}

protocol SyncService {
    func syncIfNeeded() async throws
}

struct NoOpSyncService: SyncService {
    func syncIfNeeded() async throws { }
}
