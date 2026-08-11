import Foundation

@MainActor
final class CreateExerciseViewModel: ObservableObject {
    @Published var name = ""
    @Published var repType: ExerciseRepType = .reps
    @Published var difficultyType: ExerciseDifficultyType = .weighted
    @Published var restMinutes = 2
    @Published var restSeconds = 0
    @Published var primaryMuscleID: MuscleItem.ID?
    @Published var secondaryMuscleIDs: Set<MuscleItem.ID> = []
    @Published private(set) var muscles: [MuscleItem] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSaving = false

    private let repository: any ExerciseRepository

    init(repository: any ExerciseRepository) {
        self.repository = repository
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && primaryMuscleID != nil
            && restMinutes >= 0
            && (0...59).contains(restSeconds)
    }

    var targetRestSeconds: Int { restMinutes * 60 + restSeconds }

    func load() {
        do {
            muscles = try repository.fetchMuscles()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleSecondary(_ id: MuscleItem.ID) {
        if secondaryMuscleIDs.contains(id) { secondaryMuscleIDs.remove(id) }
        else { secondaryMuscleIDs.insert(id) }
    }

    func save() -> Bool {
        guard restMinutes >= 0, (0...59).contains(restSeconds) else {
            errorMessage = "Enter minutes of 0 or more and seconds between 0 and 59."
            return false
        }
        guard let primaryMuscleID else {
            errorMessage = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Enter an exercise name." : "Select a primary muscle."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try repository.createExercise(NewExercise(
                name: name,
                repType: repType,
                difficultyType: difficultyType,
                targetRestSeconds: targetRestSeconds,
                primaryMuscleID: primaryMuscleID,
                secondaryMuscleIDs: secondaryMuscleIDs.subtracting([primaryMuscleID])
            ))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
