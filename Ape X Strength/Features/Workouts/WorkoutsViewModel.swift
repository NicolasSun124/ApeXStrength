import CoreData
import Foundation
import SwiftUI

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

    func didCreateWorkout() { load() }
}

@MainActor
final class CreateWorkoutViewModel: ObservableObject {
    @Published var name = ""
    @Published var selectedExercises: [ExerciseListItem] = []
    @Published var selectedTagIDs: Set<NSManagedObjectID> = []
    @Published var plannedSets: [NSManagedObjectID: [WorkoutSetDraft]] = [:]
    @Published private(set) var exercises: [ExerciseListItem] = []
    @Published private(set) var tags: [TagItem] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSaving = false
    private let repository: any WorkoutRepository

    init(repository: any WorkoutRepository) { self.repository = repository }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !selectedExercises.isEmpty
    }

    func load() {
        do {
            exercises = try repository.fetchAvailableExercises()
            tags = try repository.fetchTags()
        } catch { errorMessage = error.localizedDescription }
    }

    func addExercises(_ ids: Set<NSManagedObjectID>) {
        let alreadySelected = Set(selectedExercises.map(\.id))
        selectedExercises.append(contentsOf: exercises.filter { ids.contains($0.id) && !alreadySelected.contains($0.id) })
    }

    func removeExercises(at offsets: IndexSet) {
        let ids = offsets.map { selectedExercises[$0].id }
        selectedExercises.remove(atOffsets: offsets)
        ids.forEach { plannedSets.removeValue(forKey: $0) }
    }
    func moveExercises(from source: IndexSet, to destination: Int) { selectedExercises.move(fromOffsets: source, toOffset: destination) }

    func addSet(to exerciseID: NSManagedObjectID) {
        plannedSets[exerciseID, default: []].append(WorkoutSetDraft())
    }

    func removeSet(_ setID: UUID, from exerciseID: NSManagedObjectID) {
        plannedSets[exerciseID]?.removeAll { $0.id == setID }
    }

    func setBinding(for exerciseID: NSManagedObjectID, setID: UUID) -> Binding<WorkoutSetDraft> {
        Binding(
            get: { self.plannedSets[exerciseID]?.first(where: { $0.id == setID }) ?? WorkoutSetDraft() },
            set: { updated in
                guard let index = self.plannedSets[exerciseID]?.firstIndex(where: { $0.id == setID }) else { return }
                self.plannedSets[exerciseID]?[index] = updated
            }
        )
    }

    func addTag(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let tag = try repository.createTag(named: name)
            if !tags.contains(where: { $0.id == tag.id }) {
                tags.append(tag)
                tags.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
            selectedTagIDs.insert(tag.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() -> Bool {
        guard isValid else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try repository.createWorkout(NewWorkout(
                name: name,
                exerciseIDs: selectedExercises.map(\.id),
                selectedTagIDs: selectedTagIDs,
                plannedSetsByExerciseID: Dictionary(uniqueKeysWithValues: selectedExercises.map { exercise in
                    let sets = (plannedSets[exercise.id] ?? []).map { draft in
                        NewPlannedSet(
                            reps: exercise.repType == .reps ? Int(draft.performanceValue) : nil,
                            timeSeconds: exercise.repType == .time ? Double(draft.performanceValue) : nil,
                            distance: exercise.repType == .distance ? Decimal(string: draft.performanceValue) : nil,
                            weight: exercise.difficultyType == .bodyweight ? nil : Decimal(string: draft.weightValue)
                        )
                    }
                    return (exercise.id, sets)
                })
            ))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
