import CoreData
import Foundation

struct WorkoutListItem: Identifiable, Equatable {
    let id: NSManagedObjectID
    let name: String
    let exerciseCount: Int
    let updatedAt: Date
}

struct TagItem: Identifiable, Hashable {
    let id: NSManagedObjectID
    let name: String

    var color: TagColor { TagColor(name: name) }
}

struct TagColor: Hashable {
    let red: Double
    let green: Double
    let blue: Double

    init(name: String) {
        let palette: [(Double, Double, Double)] = [
            (0.39, 0.95, 0.73),
            (0.66, 1.00, 0.38),
            (0.10, 0.12, 0.96),
            (1.00, 0.49, 0.62),
            (1.00, 0.73, 0.28),
            (0.55, 0.66, 1.00)
        ]
        let value = name.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        let selected = palette[abs(value) % palette.count]
        red = selected.0
        green = selected.1
        blue = selected.2
    }
}

struct NewWorkout {
    let name: String
    let exerciseIDs: [NSManagedObjectID]
    let selectedTagIDs: Set<NSManagedObjectID>
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
