import CoreData
import Foundation
import SwiftUI

@MainActor
final class WorkoutsViewModel: ObservableObject {
    @Published private(set) var state: ViewLoadState = .idle
    @Published private(set) var workouts: [WorkoutListItem] = []
    @Published private(set) var activeSessionDraft: WorkoutSessionDraft?
    @Published private(set) var draftErrorMessage: String?
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

    func detectActiveSessionDraft() {
        do {
            activeSessionDraft = try repository.fetchActiveSessionDraft()
            draftErrorMessage = nil
        } catch {
            draftErrorMessage = error.localizedDescription
        }
    }

    func discardActiveSessionDraft() {
        guard let draft = activeSessionDraft else { return }
        do {
            try repository.discardSession(id: draft.id)
            activeSessionDraft = nil
            draftErrorMessage = nil
        } catch {
            draftErrorMessage = error.localizedDescription
        }
    }

    func clearActiveSessionDraft() {
        activeSessionDraft = nil
    }

    func dismissDraftError() {
        draftErrorMessage = nil
    }
}

@MainActor
final class WorkoutPreviewViewModel: ObservableObject {
    @Published private(set) var state: ViewLoadState = .idle
    @Published private(set) var workout: WorkoutPreview?
    @Published private(set) var availableExercises: [ExerciseListItem] = []
    @Published private(set) var archiveErrorMessage: String?
    @Published private(set) var editErrorMessage: String?
    @Published private(set) var isArchiving = false
    private let workoutID: NSManagedObjectID
    private let repository: any WorkoutRepository

    init(workoutID: NSManagedObjectID, repository: any WorkoutRepository) {
        self.workoutID = workoutID
        self.repository = repository
    }

    func load() {
        state = .loading
        do {
            workout = try repository.fetchWorkoutPreview(id: workoutID)
            availableExercises = try repository.fetchAvailableExercises()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func archive() -> Bool {
        isArchiving = true
        defer { isArchiving = false }
        do {
            try repository.archiveWorkout(id: workoutID)
            archiveErrorMessage = nil
            return true
        } catch {
            archiveErrorMessage = error.localizedDescription
            return false
        }
    }

    func dismissArchiveError() {
        archiveErrorMessage = nil
    }

    func removeExercise(id: NSManagedObjectID) -> Bool {
        do {
            try repository.removeExercise(id: id, fromWorkout: workoutID)
            editErrorMessage = nil
            load()
            return true
        } catch {
            editErrorMessage = error.localizedDescription
            return false
        }
    }

    func reorderExercises(_ exerciseIDs: [NSManagedObjectID]) -> Bool {
        do {
            try repository.reorderExercises(exerciseIDs, inWorkout: workoutID)
            editErrorMessage = nil
            load()
            return true
        } catch {
            editErrorMessage = error.localizedDescription
            return false
        }
    }

    func dismissEditError() {
        editErrorMessage = nil
    }

    func setAlternateExercises(_ ids: Set<NSManagedObjectID>, for exerciseID: NSManagedObjectID) -> Bool {
        do {
            try repository.setAlternateExercises(ids, forExercise: exerciseID, inWorkout: workoutID)
            editErrorMessage = nil
            load()
            return true
        } catch {
            editErrorMessage = error.localizedDescription
            return false
        }
    }

    func replaceExercise(_ exerciseID: NSManagedObjectID, with alternateID: NSManagedObjectID) -> Bool {
        do {
            try repository.replaceExercise(exerciseID, with: alternateID, inWorkout: workoutID)
            editErrorMessage = nil
            load()
            return true
        } catch {
            editErrorMessage = error.localizedDescription
            return false
        }
    }
}

@MainActor
final class CreateWorkoutViewModel: ObservableObject {
    @Published var name = ""
    @Published var selectedExercises: [ExerciseListItem] = []
    @Published var selectedTagIDs: Set<NSManagedObjectID> = []
    @Published var plannedSets: [NSManagedObjectID: [WorkoutSetDraft]] = [:]
    @Published var alternateExerciseIDs: [NSManagedObjectID: Set<NSManagedObjectID>] = [:]
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
        ids.forEach { alternateExerciseIDs.removeValue(forKey: $0) }
    }
    func moveExercises(from source: IndexSet, to destination: Int) { selectedExercises.move(fromOffsets: source, toOffset: destination) }

    func reorderExercises(_ exercises: [ExerciseListItem]) {
        selectedExercises = exercises
    }

    func replaceExercise(_ current: ExerciseListItem, with alternate: ExerciseListItem) {
        guard let index = selectedExercises.firstIndex(where: { $0.id == current.id }),
              !selectedExercises.contains(where: { $0.id == alternate.id }) else { return }

        var alternates = alternateExerciseIDs.removeValue(forKey: current.id) ?? []
        alternates.remove(alternate.id)
        alternates.insert(current.id)
        alternateExerciseIDs[alternate.id] = alternates

        if let sets = plannedSets.removeValue(forKey: current.id) {
            plannedSets[alternate.id] = sets
        }
        selectedExercises[index] = alternate
    }

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
                }),
                alternateExerciseIDsByExerciseID: alternateExerciseIDs
            ))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
