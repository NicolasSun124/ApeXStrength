import CoreData
import Foundation

struct WorkoutListItem: Identifiable, Equatable {
    let id: NSManagedObjectID
    let name: String
    let exerciseCount: Int
    let updatedAt: Date
    let tags: [WorkoutTagSummary]
    let statistics: WorkoutStatistics
}

struct WorkoutPreview: Equatable {
    let id: NSManagedObjectID
    let name: String
    let tags: [WorkoutTagSummary]
    let exercises: [WorkoutPreviewExercise]
}

struct WorkoutSessionDraft {
    let id: NSManagedObjectID
    let workout: WorkoutPreview
    let startedAt: Date
    let completedSetNumbersByExerciseID: [NSManagedObjectID: Set<Int>]
}

struct CompletedWorkoutSession {
    let id: NSManagedObjectID
    let workoutID: NSManagedObjectID
    let startedAt: Date
    let endedAt: Date
    let rating: Int
    let note: String?
    let exercises: [CompletedSessionExercise]
}

struct CompletedSessionExercise: Equatable {
    let exerciseID: NSManagedObjectID
    let sets: [CompletedSessionSet]
}

struct CompletedSessionSet: Equatable {
    let number: Int
    let reps: Int
    let timeSeconds: Double
    let distance: Decimal
    let weight: Decimal
    let completed: Bool
}

struct WorkoutSessionHistoryItem: Identifiable {
    let id: NSManagedObjectID
    let workoutName: String
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int
    let volume: Decimal
    let percentCompleted: Double
    let rating: Int
    let note: String?
    let exercises: [WorkoutSessionHistoryExercise]
}

struct WorkoutSessionHistoryExercise: Identifiable {
    let id: NSManagedObjectID
    let name: String
    let primaryMuscleName: String
    let primaryMuscleColorHex: String
    let repType: ExerciseRepType
    let difficultyType: ExerciseDifficultyType
    let targetRestSeconds: Int
    let sets: [CompletedSessionSet]
}

enum ImprovementTrend {
    case improved
    case maintained
    case regressed
    case firstEntry
}

struct ExerciseImprovementSummary: Identifiable {
    let id: NSManagedObjectID
    let exerciseName: String
    let lifetime: ExerciseImprovementMetrics
    let previous: ExerciseImprovementMetrics
}

struct ExerciseImprovementMetrics {
    let metrics: [ImprovementMetric]
}

struct ImprovementMetric: Identifiable {
    var id: String { title }
    let title: String
    let displayValue: String
    let trend: ImprovementTrend
}

struct WorkoutPreviewExercise: Identifiable, Equatable {
    let id: NSManagedObjectID
    let name: String
    let primaryMuscleColorHex: String
    let repType: ExerciseRepType
    let difficultyType: ExerciseDifficultyType
    let targetRestSeconds: Int
    let sets: [WorkoutPreviewSet]
    let alternates: [ExerciseListItem]
}

struct WorkoutPreviewSet: Identifiable, Equatable {
    let id: NSManagedObjectID
    let number: Int
    let reps: Int
    let timeSeconds: Double
    let distance: Decimal
    let weight: Decimal
}

struct WorkoutTagSummary: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let color: TagColor
}

struct WorkoutStatistics: Equatable {
    let lastUsed: Date?
    let meanDurationMinutes: Double?
    let meanVolume: Decimal?
    let meanRestSeconds: Double?
    let meanIntensity: Double?
    let meanPercentCompleted: Double?

    static let empty = WorkoutStatistics(
        lastUsed: nil,
        meanDurationMinutes: nil,
        meanVolume: nil,
        meanRestSeconds: nil,
        meanIntensity: nil,
        meanPercentCompleted: nil
    )
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
        let premadeTags = [
            "upper", "lower", "core", "push", "pull", "legs", "back", "chest",
            "hypertrophy", "strength", "plyometrics", "calisthenics", "circuit",
            "beginner", "intermediate", "advanced", "endurance", "flexibility",
            "stability", "cardio", "functional", "bodyweight"
        ]
        let normalizedName = name.lowercased()
        let hue: Double
        let saturation: Double
        let lightness: Double

        if let index = premadeTags.firstIndex(of: normalizedName) {
            hue = Double(index) / Double(premadeTags.count)
            saturation = index.isMultiple(of: 2) ? 0.82 : 0.68
            lightness = index.isMultiple(of: 3) ? 0.62 : 0.54
        } else {
            let hash = name.unicodeScalars.reduce(UInt64(14_695_981_039_346_656_037)) {
                ($0 ^ UInt64($1.value)) &* 1_099_511_628_211
            }
            hue = Double(hash % 360) / 360
            saturation = 0.72
            lightness = 0.58
        }

        let rgb = Self.rgb(hue: hue, saturation: saturation, lightness: lightness)
        red = rgb.red
        green = rgb.green
        blue = rgb.blue
    }

    private static func rgb(
        hue: Double,
        saturation: Double,
        lightness: Double
    ) -> (red: Double, green: Double, blue: Double) {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = hue * 6
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let base: (Double, Double, Double)

        switch sector {
        case 0..<1: base = (chroma, x, 0)
        case 1..<2: base = (x, chroma, 0)
        case 2..<3: base = (0, chroma, x)
        case 3..<4: base = (0, x, chroma)
        case 4..<5: base = (x, 0, chroma)
        default: base = (chroma, 0, x)
        }

        let match = lightness - chroma / 2
        return (base.0 + match, base.1 + match, base.2 + match)
    }
}

struct NewWorkout {
    let name: String
    let exerciseIDs: [NSManagedObjectID]
    let selectedTagIDs: Set<NSManagedObjectID>
    let plannedSetsByExerciseID: [NSManagedObjectID: [NewPlannedSet]]
    let alternateExerciseIDsByExerciseID: [NSManagedObjectID: Set<NSManagedObjectID>]
}

struct NewPlannedSet {
    let reps: Int?
    let timeSeconds: Double?
    let distance: Decimal?
    let weight: Decimal?
}

struct WorkoutSetDraft: Identifiable, Equatable {
    let id = UUID()
    var performanceValue = ""
    var weightValue = ""

    init(performanceValue: String = "", weightValue: String = "") {
        self.performanceValue = performanceValue
        self.weightValue = weightValue
    }
}

struct ExerciseListItem: Identifiable, Equatable {
    let id: NSManagedObjectID
    let name: String
    let primaryMuscleColorHex: String
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
    let primaryMuscle: MuscleItem
    let secondaryMuscles: [MuscleItem]
    let isGlobal: Bool
    let isArchived: Bool
}

struct AppSettings: Equatable {
    var weightUnit: String
    var restTimerNotificationsEnabled: Bool
}

enum WeightUnit: String {
    case pounds = "lbs"
    case kilograms = "kg"

    private static let poundsPerKilogram = Decimal(string: "2.2046226218")!

    init(setting: String) {
        self = setting == Self.kilograms.rawValue ? .kilograms : .pounds
    }

    func pounds(fromDisplayed value: Decimal) -> Decimal {
        self == .kilograms ? value * Self.poundsPerKilogram : value
    }

    func displayed(fromPounds value: Decimal) -> Decimal {
        self == .kilograms ? value / Self.poundsPerKilogram : value
    }
}
