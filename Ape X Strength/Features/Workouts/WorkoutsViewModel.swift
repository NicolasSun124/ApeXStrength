import Foundation

@MainActor
final class WorkoutsViewModel: ObservableObject {
    @Published private(set) var state: ViewLoadState = .idle
    @Published private(set) var workouts: [WorkoutListItem] = []
    private let repository: any WorkoutRepository

    init(repository: any WorkoutRepository) {
        self.repository = repository
    }

    func load() {
        state = .loading
        do {
            workouts = try repository.fetchWorkouts()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
