import CoreData
import Foundation

struct WorkoutListItem: Identifiable, Equatable {
    let id: NSManagedObjectID
    let name: String
    let exerciseCount: Int
    let updatedAt: Date
}

struct ExerciseListItem: Identifiable, Equatable {
    let id: NSManagedObjectID
    let name: String
    let trackingType: String
    let targetRestSeconds: Int
}

struct AppSettings: Equatable {
    var weightUnit: String
    var restTimerNotificationsEnabled: Bool
}
