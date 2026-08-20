import Foundation

@MainActor
final class ExercisesViewModel: ObservableObject {
    @Published private(set) var state: ViewLoadState = .idle
    @Published private(set) var exercises: [ExerciseListItem] = []

    private let repository: any ExerciseRepository

    init(repository: any ExerciseRepository) {
        self.repository = repository
    }

    func load() {
        state = .loading
        do {
            exercises = try repository.fetchExercises()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func didCreateExercise(id: ExerciseDetail.ID) {
        do {
            let exercise = try repository.fetchExercise(id: id)
            let item = ExerciseListItem(
                id: exercise.id,
                name: exercise.name,
                primaryMuscleColorHex: exercise.primaryMuscle.colorHex,
                repType: exercise.repType,
                difficultyType: exercise.difficultyType,
                targetRestSeconds: exercise.targetRestSeconds
            )
            exercises.removeAll { $0.id == item.id }
            exercises.append(item)
            exercises.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            state = .loaded
        } catch {
            load()
        }
    }
}
