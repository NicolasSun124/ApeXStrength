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

    func didCreateExercise() {
        load()
    }
}
