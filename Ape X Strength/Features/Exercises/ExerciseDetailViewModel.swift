import CoreData
import Foundation

@MainActor
final class ExerciseDetailViewModel: ObservableObject {
    @Published private(set) var state: ViewLoadState = .idle
    @Published private(set) var exercise: ExerciseDetail?
    private var id: NSManagedObjectID
    private let repository: any ExerciseRepository

    init(id: NSManagedObjectID, repository: any ExerciseRepository) {
        self.id = id
        self.repository = repository
    }

    func load() {
        state = .loading
        do {
            exercise = try repository.fetchExercise(id: id)
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func archive() -> Bool {
        do { try repository.archiveExercise(id: id); return true }
        catch { state = .failed(error.localizedDescription); return false }
    }

    func showExercise(id: NSManagedObjectID) {
        self.id = id
        load()
    }
}
