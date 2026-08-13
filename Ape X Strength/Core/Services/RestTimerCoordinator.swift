import ActivityKit
import Combine
import Foundation
import UserNotifications

struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let endDate: Date
    }

    let workoutName: String
}

@MainActor
final class RestTimerCoordinator: ObservableObject {
    private static let notificationIdentifier = "rest-timer-finished"
    nonisolated private static let endDateKey = "restTimer.endDate"
    nonisolated private static let sessionIdentifierKey = "restTimer.sessionIdentifier"

    private let notificationCenter: UNUserNotificationCenter
    private let settings: any SettingsService
    private var activity: Activity<RestTimerAttributes>?

    init(
        notificationCenter: UNUserNotificationCenter = .current(),
        settings: any SettingsService = UserDefaultsSettingsService()
    ) {
        self.notificationCenter = notificationCenter
        self.settings = settings
    }

    nonisolated static func restoredEndDate(for sessionIdentifier: String) -> Date? {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: sessionIdentifierKey) == sessionIdentifier,
              let endDate = defaults.object(forKey: endDateKey) as? Date,
              endDate > Date() else {
            defaults.removeObject(forKey: endDateKey)
            defaults.removeObject(forKey: sessionIdentifierKey)
            return nil
        }
        return endDate
    }

    func start(until endDate: Date, workoutName: String, sessionIdentifier: String) async {
        guard endDate > Date() else { return }

        UserDefaults.standard.set(endDate, forKey: Self.endDateKey)
        UserDefaults.standard.set(sessionIdentifier, forKey: Self.sessionIdentifierKey)

        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])

        if ActivityAuthorizationInfo().areActivitiesEnabled {
            let content = ActivityContent(
                state: RestTimerAttributes.ContentState(endDate: endDate),
                staleDate: endDate
            )
            if let currentActivity = activity ?? Activity<RestTimerAttributes>.activities.first {
                activity = currentActivity
                await currentActivity.update(content)
            } else {
                let attributes = RestTimerAttributes(workoutName: workoutName)
                activity = try? Activity.request(attributes: attributes, content: content)
            }
        }

        guard settings.load().restTimerNotificationsEnabled else { return }
        let settings = await notificationCenter.notificationSettings()
        var authorizationStatus = settings.authorizationStatus
        if authorizationStatus == .notDetermined {
            _ = try? await notificationCenter.requestAuthorization(options: [.alert, .sound])
            authorizationStatus = (await notificationCenter.notificationSettings()).authorizationStatus
        }
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "Time for your next set."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, endDate.timeIntervalSinceNow),
            repeats: false
        )
        try? await notificationCenter.add(UNNotificationRequest(
            identifier: Self.notificationIdentifier,
            content: content,
            trigger: trigger
        ))
    }

    func cancel() async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
        clearPersistedTimer()

        await endActivity()
    }

    func finish() async {
        clearPersistedTimer()
        await endActivity()
    }

    private func clearPersistedTimer() {
        UserDefaults.standard.removeObject(forKey: Self.endDateKey)
        UserDefaults.standard.removeObject(forKey: Self.sessionIdentifierKey)
    }

    private func endActivity() async {

        let activities = Activity<RestTimerAttributes>.activities
        let finalContent = ActivityContent(
            state: RestTimerAttributes.ContentState(endDate: Date()),
            staleDate: nil
        )
        for activity in activities {
            await activity.end(finalContent, dismissalPolicy: .immediate)
        }
        activity = nil
    }
}
