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
    @Published private(set) var savedExerciseID: ExerciseDetail.ID?

    private let repository: any ExerciseRepository
    private let exerciseID: ExerciseDetail.ID?

    init(repository: any ExerciseRepository, exerciseID: ExerciseDetail.ID? = nil) {
        self.repository = repository
        self.exerciseID = exerciseID
    }

    var isEditing: Bool { exerciseID != nil }

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
            if let exerciseID {
                let exercise = try repository.fetchExercise(id: exerciseID)
                name = exercise.name
                repType = exercise.repType
                difficultyType = exercise.difficultyType
                restMinutes = exercise.targetRestSeconds / 60
                restSeconds = exercise.targetRestSeconds % 60
                primaryMuscleID = exercise.primaryMuscle.id
                secondaryMuscleIDs = Set(exercise.secondaryMuscles.map(\.id))
            }
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
            let input = NewExercise(
                name: name,
                repType: repType,
                difficultyType: difficultyType,
                targetRestSeconds: targetRestSeconds,
                primaryMuscleID: primaryMuscleID,
                secondaryMuscleIDs: secondaryMuscleIDs.subtracting([primaryMuscleID])
            )
            if let exerciseID {
                savedExerciseID = try repository.updateExercise(id: exerciseID, input: input)
            } else {
                savedExerciseID = try repository.createExercise(input).id
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
