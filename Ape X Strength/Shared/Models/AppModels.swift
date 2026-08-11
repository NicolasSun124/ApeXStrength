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
    let repType: ExerciseRepType
    let difficultyType: ExerciseDifficultyType
    let targetRestSeconds: Int
}

enum ExerciseRepType: String, CaseIterable, Identifiable {
    case reps = "reps"
    case time = "time"
    case distance = "distance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reps: "Reps"
        case .time: "Time"
        case .distance: "Distance"
        }
    }
}

enum ExerciseDifficultyType: String, CaseIterable, Identifiable {
    case weighted = "weighted"
    case bodyweight = "bodyweight"
    case assistedWeight = "assisted_weight"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weighted: "Weighted"
        case .bodyweight: "Bodyweight"
        case .assistedWeight: "Assisted Weight"
        }
    }
}

struct ExerciseConfiguration {
    let repType: ExerciseRepType
    let difficultyType: ExerciseDifficultyType

    var storageValue: String { "\(repType.rawValue)_\(difficultyType.rawValue)" }

    init(repType: ExerciseRepType, difficultyType: ExerciseDifficultyType) {
        self.repType = repType
        self.difficultyType = difficultyType
    }

    init(storageValue: String) {
        if storageValue == "reps_weight" {
            repType = .reps
            difficultyType = .weighted
            return
        }

        repType = ExerciseRepType.allCases.first { storageValue.hasPrefix($0.rawValue + "_") }
            ?? ExerciseRepType(rawValue: storageValue)
            ?? .reps
        difficultyType = ExerciseDifficultyType.allCases.first { storageValue.hasSuffix("_" + $0.rawValue) }
            ?? .bodyweight
    }
}

struct MuscleItem: Identifiable, Hashable {
    let id: NSManagedObjectID
    let name: String
    let colorHex: String
}

struct NewExercise: Equatable {
    let name: String
    let repType: ExerciseRepType
    let difficultyType: ExerciseDifficultyType
    let targetRestSeconds: Int
    let primaryMuscleID: NSManagedObjectID
    let secondaryMuscleIDs: Set<NSManagedObjectID>
}

struct ExerciseDetail: Identifiable, Equatable {
    let id: NSManagedObjectID
    let name: String
    let repType: ExerciseRepType
    let difficultyType: ExerciseDifficultyType
    let targetRestSeconds: Int
    let primaryMuscle: String
    let secondaryMuscles: [String]
}

struct AppSettings: Equatable {
    var weightUnit: String
    var restTimerNotificationsEnabled: Bool
}
