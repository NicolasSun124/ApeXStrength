import CoreData
import SwiftUI
import UIKit

struct ActiveWorkoutView: View {
    let workout: WorkoutPreview
    let sessionID: NSManagedObjectID
    private let repository: any WorkoutRepository
    private let onSessionSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var exercises: [ActiveWorkoutExercise]
    @State private var availableExercises: [ExerciseListItem] = []
    @State private var isSelectingExercise = false
    @State private var isReorderingExercises = false
    @State private var exerciseChoosingAlternates: ActiveWorkoutExercise?
    @State private var startedAt: Date
    @State private var restTimerEnd: Date?
    @State private var isRestTimerPresented = false
    @State private var isConfirmingAbort = false
    @State private var abortErrorMessage: String?
    @State private var autosaveErrorMessage: String?
    @State private var isShowingFinishSummary = false
    @State private var editingTimeSet: TimeSetTarget?
    @State private var timePickerMinutes = 0
    @State private var timePickerSeconds = 0
    @StateObject private var restTimerCoordinator = RestTimerCoordinator()
    @FocusState private var isNumericFieldFocused: Bool

    init(
        workout: WorkoutPreview,
        sessionID: NSManagedObjectID,
        startedAt: Date,
        repository: any WorkoutRepository,
        onSessionSaved: @escaping () -> Void = {}
    ) {
        self.workout = workout
        self.sessionID = sessionID
        self.repository = repository
        self.onSessionSaved = onSessionSaved
        _exercises = State(initialValue: workout.exercises.map(ActiveWorkoutExercise.init))
        _startedAt = State(initialValue: startedAt)
        _restTimerEnd = State(initialValue: RestTimerCoordinator.restoredEndDate(
            for: sessionID.uriRepresentation().absoluteString
        ))
    }

    init(
        draft: WorkoutSessionDraft,
        repository: any WorkoutRepository,
        onSessionSaved: @escaping () -> Void = {}
    ) {
        workout = draft.workout
        sessionID = draft.id
        self.repository = repository
        self.onSessionSaved = onSessionSaved
        _exercises = State(initialValue: draft.workout.exercises.map { exercise in
            ActiveWorkoutExercise(
                exercise,
                completedSetNumbers: draft.completedSetNumbersByExerciseID[exercise.id] ?? [],
                completedAtBySetNumber: draft.completedAtByExerciseIDAndSetNumber[exercise.id] ?? [:]
            )
        })
        _startedAt = State(initialValue: draft.startedAt)
        _restTimerEnd = State(initialValue: RestTimerCoordinator.restoredEndDate(
            for: draft.id.uriRepresentation().absoluteString
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            sessionControls
                .padding(.horizontal, ApeSpacing.md)
                .padding(.vertical, ApeSpacing.sm)
                .background(ApeColor.background)

            Divider()
                .overlay(ApeColor.divider.opacity(0.25))

            ScrollView {
                VStack(spacing: ApeSpacing.md) {
                    ForEach($exercises) { $exercise in
                        exerciseCard(exercise: $exercise)
                    }

                    Button {
                        loadAvailableExercises()
                        isSelectingExercise = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus")
                    }
                    .buttonStyle(ApeSecondaryButtonStyle())
                }
                .padding(ApeSpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(ApeColor.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ApeColor.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(workout.name)
                    .font(.apeHeadline)
                    .foregroundStyle(ApeColor.textPrimary)
                    .lineLimit(1)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isNumericFieldFocused = false }
            }
        }
        .sheet(isPresented: $isSelectingExercise) {
            ActiveExercisePicker(
                exercises: availableExercises.filter { candidate in
                    !exercises.contains { $0.exerciseID == candidate.id }
                },
                onSelect: addExercise
            )
        }
        .sheet(isPresented: $isReorderingExercises) {
            ActiveExerciseReorderView(exercises: exercises) { exercises = $0 }
        }
        .sheet(item: $exerciseChoosingAlternates) { exercise in
            ActiveAlternateExercisePicker(
                exercises: availableExercises.filter { candidate in
                    candidate.id != exercise.exerciseID
                        && !exercises.contains(where: { $0.exerciseID == candidate.id })
                },
                selection: Set(exercise.alternates.map(\.id))
            ) { selection in
                setAlternates(selection, for: exercise.id)
            }
        }
        .sheet(isPresented: $isRestTimerPresented) {
            RestTimerView(endDate: $restTimerEnd)
                .presentationDetents([.height(230)])
                .presentationDragIndicator(.visible)
                .presentationBackground(ApeColor.primarySoft)
        }
        .sheet(item: $editingTimeSet) { _ in
            SetTimePickerView(
                minutes: $timePickerMinutes,
                seconds: $timePickerSeconds,
                onDone: savePickedTime
            )
            .presentationDetents([.height(310)])
            .presentationDragIndicator(.visible)
            .presentationBackground(ApeColor.surface)
        }
        .confirmationDialog(
            "Abort this session?",
            isPresented: $isConfirmingAbort,
            titleVisibility: .visible
        ) {
            Button("Abort Session", role: .destructive) {
                abortSession()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your active session and all of its progress will be deleted without being saved.")
        }
        .alert(
            "Couldn’t Abort Session",
            isPresented: Binding(
                get: { abortErrorMessage != nil },
                set: { if !$0 { abortErrorMessage = nil } }
            )
        ) {
            Button("OK") { abortErrorMessage = nil }
        } message: {
            Text(abortErrorMessage ?? "Please try again.")
        }
        .alert(
            "Couldn’t Autosave Session",
            isPresented: Binding(
                get: { autosaveErrorMessage != nil },
                set: { if !$0 { autosaveErrorMessage = nil } }
            )
        ) {
            Button("OK") { autosaveErrorMessage = nil }
        } message: {
            Text(autosaveErrorMessage ?? "Your latest changes haven’t been saved yet.")
        }
        .navigationDestination(isPresented: $isShowingFinishSummary) {
            WorkoutFinishView(
                workoutName: workout.name,
                improvements: currentImprovements()
            ) { shouldSave, rating, note in
                finishSession(shouldSave: shouldSave, rating: rating, note: note)
            }
        }
        .task { loadAvailableExercises() }
        .task(id: currentSessionExercises()) { await autosaveSession() }
        .task(id: restTimerEnd) { await clearRestTimerWhenFinished() }
    }

    private var sessionControls: some View {
        HStack(spacing: ApeSpacing.sm) {
            if ProcessInfo.processInfo.environment["APE_X_UI_TESTING"] == "1" {
                Label(elapsedTime(at: startedAt), systemImage: "timer")
                    .font(.apeHeadline.monospacedDigit())
                    .foregroundStyle(ApeColor.textPrimary)
                    .accessibilityLabel("Workout time 00:00:00")
            } else {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    Label(elapsedTime(at: context.date), systemImage: "timer")
                        .font(.apeHeadline.monospacedDigit())
                        .foregroundStyle(ApeColor.textPrimary)
                        .accessibilityLabel("Workout time \(elapsedTime(at: context.date))")
                }
            }

            if let restTimerEnd {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    Button {
                        isRestTimerPresented = true
                    } label: {
                        Label(restTime(at: context.date, endDate: restTimerEnd), systemImage: "hourglass")
                            .font(.apeCallout.monospacedDigit())
                            .foregroundStyle(ApeColor.accent)
                    }
                    .accessibilityLabel("Rest timer \(restTime(at: context.date, endDate: restTimerEnd))")
                }
            }

            Spacer()

            Menu {
                Button("Abort Session", systemImage: "xmark.circle", role: .destructive) {
                    isConfirmingAbort = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(ApeColor.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(ApeColor.control)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityLabel("Workout options")

            Button("Finish") { isShowingFinishSummary = true }
                .font(.apeHeadline)
                .foregroundStyle(ApeColor.background)
                .padding(.horizontal, ApeSpacing.md)
                .frame(height: 42)
                .background(ApeColor.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func exerciseCard(exercise: Binding<ActiveWorkoutExercise>) -> some View {
        VStack(alignment: .leading, spacing: ApeSpacing.sm) {
            HStack(spacing: ApeSpacing.sm) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: exercise.wrappedValue.primaryMuscleColorHex))
                    .frame(width: 38, height: 38)
                Text(exercise.wrappedValue.name)
                    .font(.apeHeadline)
                    .foregroundStyle(ApeColor.textPrimary)
                Spacer()
                if !exercise.wrappedValue.alternates.isEmpty {
                    Menu {
                        ForEach(exercise.wrappedValue.alternates) { alternate in
                            Button {
                                replaceExercise(exercise.wrappedValue.id, with: alternate)
                            } label: {
                                Label(alternate.name, systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(ApeColor.textPrimary)
                            .padding()
                    }
                    .accessibilityLabel("Show alternates for \(exercise.wrappedValue.name)")
                }
                Menu {
                    Button("Alternate Exercises", systemImage: "arrow.triangle.2.circlepath") {
                        exerciseChoosingAlternates = exercise.wrappedValue
                    }
                    Button("Reorder", systemImage: "arrow.up.arrow.down") {
                        isReorderingExercises = true
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        removeExercise(exercise.wrappedValue.id)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(ApeColor.textPrimary)
                        .padding()
                }
                .accessibilityLabel("Options for \(exercise.wrappedValue.name)")
            }

            HStack(spacing: ApeSpacing.xs) {
                header("Set", width: 42)
                header(performanceTitle(exercise.wrappedValue.repType))
                header(exercise.wrappedValue.difficultyType == .assistedWeight ? "Assisted" : "Weight")
                header("Done", width: 42)
            }

            ForEach(exercise.sets) { $set in
                ActiveSetSwipeToRemove {
                    exercise.wrappedValue.removeSet(id: set.id)
                } content: { HStack(spacing: ApeSpacing.xs) {
                    value("\(set.number)", width: 42)
                    if exercise.wrappedValue.repType == .reps {
                        editableInteger($set.reps, accessibilityLabel: "Reps for set \(set.number)")
                    } else if exercise.wrappedValue.repType == .time {
                        timeButton(
                            set.timeText,
                            exerciseID: exercise.wrappedValue.id,
                            setID: set.id,
                            accessibilityLabel: "Time for set \(set.number)"
                        )
                    } else {
                        editableDecimal($set.distance, accessibilityLabel: "Distance for set \(set.number)")
                    }
                    if exercise.wrappedValue.difficultyType == .bodyweight {
                        value("–")
                    } else {
                        editableDecimal($set.weight, accessibilityLabel: "Weight for set \(set.number)")
                    }
                    Button {
                        let isFinishing = !set.isCompleted
                        set.isCompleted.toggle()
                        set.completedAt = isFinishing ? Date() : nil
                        if isFinishing {
                            startRestTimer(seconds: exercise.wrappedValue.targetRestSeconds)
                        }
                    } label: {
                        Image(systemName: set.isCompleted ? "checkmark" : "")
                            .font(.apeHeadline)
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(set.isCompleted ? ApeColor.success : ApeColor.control)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .accessibilityLabel(set.isCompleted ? "Mark set incomplete" : "Mark set complete")
                } }
                .accessibilityAction(named: "Remove set \(set.number)") {
                    exercise.wrappedValue.removeSet(id: set.id)
                }
            }

            Button("Add Set") {
                exercise.wrappedValue.addSet()
            }
            .font(.apeBody)
            .foregroundStyle(ApeColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(ApeColor.control)
            .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control))
        }
        .padding(ApeSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ApeColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: ApeRadius.card))
    }

    private func loadAvailableExercises() {
        do { availableExercises = try repository.fetchAvailableExercises() }
        catch { availableExercises = [] }
    }

    private func addExercise(_ exercise: ExerciseListItem) {
        exercises.append(ActiveWorkoutExercise(exercise: exercise))
    }

    private func removeExercise(_ id: UUID) {
        exercises.removeAll { $0.id == id }
    }

    private func setAlternates(_ ids: Set<NSManagedObjectID>, for id: UUID) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        exercises[index].alternates = availableExercises
            .filter { ids.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func replaceExercise(_ id: UUID, with alternate: ExerciseListItem) {
        guard let index = exercises.firstIndex(where: { $0.id == id }),
              !exercises.contains(where: { $0.id != id && $0.exerciseID == alternate.id }) else { return }
        let current = exercises[index]
        var alternates = current.alternates.filter { $0.id != alternate.id }
        alternates.append(current.listItem)
        exercises[index] = ActiveWorkoutExercise(
            exercise: alternate,
            sets: current.sets,
            alternates: alternates.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        )
    }

    private func finishSession(shouldSave: Bool, rating: Int, note: String) -> String? {
        do {
            if shouldSave {
                try repository.saveCompletedSession(CompletedWorkoutSession(
                    id: sessionID,
                    workoutID: workout.id,
                    startedAt: startedAt,
                    endedAt: Date(),
                    rating: rating,
                    note: normalizedNote(note),
                    exercises: exercises.map { exercise in
                        CompletedSessionExercise(
                            exerciseID: exercise.exerciseID,
                            sets: exercise.sets.map { set in
                                CompletedSessionSet(
                                    number: set.number,
                                    reps: set.reps,
                                    timeSeconds: set.timeSeconds,
                                    distance: set.distance,
                                    weight: set.weight,
                                    completed: set.isCompleted,
                                    completedAt: set.completedAt
                                )
                            }
                        )
                    }
                ))
            } else {
                try repository.discardSession(id: sessionID)
            }
        } catch {
            return error.localizedDescription
        }

        closeFinishedSession()
        return nil
    }

    private func normalizedNote(_ note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func abortSession() {
        do {
            try repository.discardSession(id: sessionID)
            Task { await restTimerCoordinator.cancel() }
            restTimerEnd = nil
            dismiss()
        } catch {
            // Keep the active workout open so the persisted session is not
            // silently left behind after a failed delete.
            abortErrorMessage = error.localizedDescription
        }
    }

    private func currentSessionExercises() -> [CompletedSessionExercise] {
        exercises.map { exercise in
            CompletedSessionExercise(
                exerciseID: exercise.exerciseID,
                sets: exercise.sets.map { set in
                    CompletedSessionSet(
                        number: set.number,
                        reps: set.reps,
                        timeSeconds: set.timeSeconds,
                        distance: set.distance,
                        weight: set.weight,
                        completed: set.isCompleted,
                        completedAt: set.completedAt
                    )
                }
            )
        }
    }

    private func autosaveSession() async {
        do {
            try await Task.sleep(for: .milliseconds(500))
            try Task.checkCancellation()
            try repository.updateActiveSession(id: sessionID, exercises: currentSessionExercises())
            autosaveErrorMessage = nil
        } catch is CancellationError {
            // A newer edit replaced this pending save.
        } catch {
            autosaveErrorMessage = error.localizedDescription
        }
    }

    private func currentImprovements() -> [ExerciseImprovementSummary] {
        (try? repository.calculateImprovements(for: currentSessionExercises())) ?? []
    }

    private func closeFinishedSession() {
        Task { await restTimerCoordinator.cancel() }
        restTimerEnd = nil
        isShowingFinishSummary = false

        // The summary must leave the navigation stack before its parent active
        // workout can be dismissed. Otherwise SwiftUI ignores the parent dismiss.
        DispatchQueue.main.async {
            dismiss()
            onSessionSaved()
        }
    }

    private func elapsedTime(at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(startedAt)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }

    private func restTime(at date: Date, endDate: Date) -> String {
        Self.timerText(seconds: max(0, Int(ceil(endDate.timeIntervalSince(date)))))
    }

    private func startRestTimer(seconds: Int) {
        restTimerEnd = Date().addingTimeInterval(TimeInterval(max(0, seconds)))
        isRestTimerPresented = true
    }

    private func clearRestTimerWhenFinished() async {
        guard let scheduledEnd = restTimerEnd else { return }
        await restTimerCoordinator.start(
            until: scheduledEnd,
            workoutName: workout.name,
            sessionIdentifier: sessionID.uriRepresentation().absoluteString
        )
        let delay = max(0, scheduledEnd.timeIntervalSinceNow)
        do {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        } catch {
            return
        }
        guard restTimerEnd == scheduledEnd else { return }

        await restTimerCoordinator.finish()
        restTimerEnd = nil
        isRestTimerPresented = false
    }

    static func timerText(seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func header(_ text: String, width: CGFloat? = nil) -> some View {
        Text(text).font(.apeCaption).foregroundStyle(ApeColor.textSecondary)
            .frame(maxWidth: width == nil ? .infinity : nil).frame(width: width)
    }

    private func value(_ text: String, width: CGFloat? = nil) -> some View {
        Text(text).font(.apeBody).foregroundStyle(ApeColor.textPrimary)
            .frame(maxWidth: width == nil ? .infinity : nil, minHeight: 42).frame(width: width)
            .background(ApeColor.control).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func editableInteger(_ value: Binding<Int>, accessibilityLabel: String) -> some View {
        TextField("0", value: value, format: .number)
            .keyboardType(.numberPad)
            .focused($isNumericFieldFocused)
            .multilineTextAlignment(.center)
            .font(.apeBody)
            .foregroundStyle(ApeColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(ApeColor.control)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(accessibilityLabel)
    }

    private func editableDecimal(_ value: Binding<Decimal>, accessibilityLabel: String) -> some View {
        TextField("0", value: value, format: .number.precision(.fractionLength(0...2)))
            .keyboardType(.decimalPad)
            .focused($isNumericFieldFocused)
            .multilineTextAlignment(.center)
            .font(.apeBody)
            .foregroundStyle(ApeColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(ApeColor.control)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(accessibilityLabel)
    }

    private func timeButton(
        _ value: String,
        exerciseID: UUID,
        setID: UUID,
        accessibilityLabel: String
    ) -> some View {
        Button {
            let parts = value.split(separator: ":", omittingEmptySubsequences: false)
            timePickerMinutes = parts.first.flatMap { Int($0) } ?? 0
            timePickerSeconds = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            editingTimeSet = TimeSetTarget(exerciseID: exerciseID, setID: setID)
        } label: {
            Text(value)
                .font(.apeBody.monospacedDigit())
                .foregroundStyle(ApeColor.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(ApeColor.control)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens minutes and seconds picker")
    }

    private func savePickedTime() {
        guard let target = editingTimeSet,
              let exerciseIndex = exercises.firstIndex(where: { $0.id == target.exerciseID }),
              let setIndex = exercises[exerciseIndex].sets.firstIndex(where: { $0.id == target.setID }) else {
            editingTimeSet = nil
            return
        }
        exercises[exerciseIndex].sets[setIndex].timeText = String(
            format: "%d:%02d",
            timePickerMinutes,
            timePickerSeconds
        )
        editingTimeSet = nil
    }

    private func performanceTitle(_ type: ExerciseRepType) -> String {
        switch type { case .reps: "Reps"; case .time: "Time"; case .distance: "Distance" }
    }

    private func performanceValue(_ set: ActiveWorkoutSet, repType: ExerciseRepType) -> String {
        switch repType {
        case .reps: "\(set.reps)"
        case .time: formattedTime(set.timeSeconds)
        case .distance: decimalText(set.distance)
        }
    }

    private func decimalText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).doubleValue.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func formattedTime(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

}

private struct ActiveSetSwipeToRemove<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var offset: CGFloat = 0

    init(action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive, action: action) {
                Image(systemName: "trash.fill").foregroundStyle(.white).frame(width: 62, height: 42)
            }
            .background(ApeColor.destructive)
            .opacity(offset < 0 ? 1 : 0)
            content
                .offset(x: offset)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            offset = min(0, max(-140, value.translation.width))
                        }
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            if offset < -105 {
                                withAnimation(.easeOut(duration: 0.18)) { offset = -400 }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: action)
                            } else {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                    offset = offset < -32 ? -62 : 0
                                }
                            }
                        }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ActiveWorkoutExercise: Identifiable {
    let id = UUID()
    let exerciseID: NSManagedObjectID
    let name: String
    let primaryMuscleColorHex: String
    let repType: ExerciseRepType
    let difficultyType: ExerciseDifficultyType
    let targetRestSeconds: Int
    var sets: [ActiveWorkoutSet]
    var alternates: [ExerciseListItem]

    init(_ exercise: WorkoutPreviewExercise) {
        exerciseID = exercise.id
        name = exercise.name
        primaryMuscleColorHex = exercise.primaryMuscleColorHex
        repType = exercise.repType
        difficultyType = exercise.difficultyType
        targetRestSeconds = exercise.targetRestSeconds
        sets = exercise.sets.map(ActiveWorkoutSet.init)
        alternates = exercise.alternates
    }

    init(
        _ exercise: WorkoutPreviewExercise,
        completedSetNumbers: Set<Int>,
        completedAtBySetNumber: [Int: Date]
    ) {
        exerciseID = exercise.id
        name = exercise.name
        primaryMuscleColorHex = exercise.primaryMuscleColorHex
        repType = exercise.repType
        difficultyType = exercise.difficultyType
        targetRestSeconds = exercise.targetRestSeconds
        sets = exercise.sets.map {
            ActiveWorkoutSet(
                $0,
                isCompleted: completedSetNumbers.contains($0.number),
                completedAt: completedAtBySetNumber[$0.number]
            )
        }
        alternates = exercise.alternates
    }

    init(exercise: ExerciseListItem) {
        exerciseID = exercise.id
        name = exercise.name
        primaryMuscleColorHex = exercise.primaryMuscleColorHex
        repType = exercise.repType
        difficultyType = exercise.difficultyType
        targetRestSeconds = exercise.targetRestSeconds
        sets = []
        alternates = []
    }

    init(exercise: ExerciseListItem, sets: [ActiveWorkoutSet], alternates: [ExerciseListItem]) {
        exerciseID = exercise.id
        name = exercise.name
        primaryMuscleColorHex = exercise.primaryMuscleColorHex
        repType = exercise.repType
        difficultyType = exercise.difficultyType
        targetRestSeconds = exercise.targetRestSeconds
        self.sets = sets
        self.alternates = alternates
    }

    var listItem: ExerciseListItem {
        ExerciseListItem(
            id: exerciseID,
            name: name,
            primaryMuscleColorHex: primaryMuscleColorHex,
            repType: repType,
            difficultyType: difficultyType,
            targetRestSeconds: targetRestSeconds
        )
    }

    mutating func addSet() {
        sets.append(ActiveWorkoutSet(number: sets.count + 1))
    }

    mutating func removeSet(id: UUID) {
        sets.removeAll { $0.id == id }
        for index in sets.indices { sets[index].number = index + 1 }
    }
}

private struct ActiveAlternateExercisePicker: View {
    let exercises: [ExerciseListItem]
    let onDone: (Set<NSManagedObjectID>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pending: Set<NSManagedObjectID>
    @State private var searchText = ""

    init(
        exercises: [ExerciseListItem],
        selection: Set<NSManagedObjectID>,
        onDone: @escaping (Set<NSManagedObjectID>) -> Void
    ) {
        self.exercises = exercises
        self.onDone = onDone
        _pending = State(initialValue: selection)
    }

    var body: some View {
        NavigationStack {
            List(filteredExercises) { exercise in
                Button {
                    if pending.contains(exercise.id) {
                        pending.remove(exercise.id)
                    } else {
                        pending.insert(exercise.id)
                    }
                } label: {
                    HStack(spacing: ApeSpacing.md) {
                        Circle()
                            .fill(Color(hex: exercise.primaryMuscleColorHex))
                            .frame(width: 18, height: 18)
                        Text(exercise.name).foregroundStyle(ApeColor.textPrimary)
                        Spacer()
                        if pending.contains(exercise.id) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(ApeColor.primary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(ApeColor.surface)
            }
            .scrollContentBackground(.hidden)
            .background(ApeColor.background)
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Alternate Exercises")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(pending); dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var filteredExercises: [ExerciseListItem] {
        searchText.isEmpty ? exercises : exercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}

private struct ActiveExerciseReorderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var exercises: [ActiveWorkoutExercise]
    let onFinish: ([ActiveWorkoutExercise]) -> Void

    init(exercises: [ActiveWorkoutExercise], onFinish: @escaping ([ActiveWorkoutExercise]) -> Void) {
        _exercises = State(initialValue: exercises)
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            ActiveExerciseReorderTable(exercises: $exercises)
                .background(ApeColor.background)
                .navigationTitle("Reorder Exercises")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Finish") { onFinish(exercises); dismiss() }
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}

private struct ActiveExerciseReorderTable: UIViewControllerRepresentable {
    @Binding var exercises: [ActiveWorkoutExercise]

    func makeCoordinator() -> Coordinator { Coordinator(exercises: $exercises) }

    func makeUIViewController(context: Context) -> UITableViewController {
        let controller = UITableViewController(style: .insetGrouped)
        controller.tableView.dataSource = context.coordinator
        controller.tableView.delegate = context.coordinator
        controller.tableView.backgroundColor = UIColor(ApeColor.background)
        controller.tableView.separatorColor = UIColor(ApeColor.control)
        controller.tableView.allowsSelection = false
        controller.tableView.setEditing(true, animated: false)
        return controller
    }

    func updateUIViewController(_ controller: UITableViewController, context: Context) {
        context.coordinator.exercises = $exercises
        let ids = exercises.map(\.id)
        guard ids != context.coordinator.displayedIDs else { return }
        context.coordinator.displayedIDs = ids
        controller.tableView.reloadData()
    }

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        var exercises: Binding<[ActiveWorkoutExercise]>
        var displayedIDs: [UUID]

        init(exercises: Binding<[ActiveWorkoutExercise]>) {
            self.exercises = exercises
            displayedIDs = exercises.wrappedValue.map(\.id)
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            exercises.wrappedValue.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let identifier = "ActiveExerciseReorderCell"
            let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
                ?? UITableViewCell(style: .default, reuseIdentifier: identifier)
            let exercise = exercises.wrappedValue[indexPath.row]
            var content = cell.defaultContentConfiguration()
            content.image = UIImage(systemName: "circle.fill")
            content.imageProperties.tintColor = UIColor(Color(hex: exercise.primaryMuscleColorHex))
            content.text = exercise.name
            content.textProperties.color = UIColor(ApeColor.textPrimary)
            content.textProperties.font = UIFont.preferredFont(forTextStyle: .headline)
            cell.contentConfiguration = content
            cell.backgroundColor = UIColor(ApeColor.surface)
            cell.showsReorderControl = true
            return cell
        }

        func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { true }

        func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
            var reordered = exercises.wrappedValue
            reordered.insert(reordered.remove(at: source.row), at: destination.row)
            displayedIDs = reordered.map(\.id)
            exercises.wrappedValue = reordered
        }
    }
}

private struct RestTimerView: View {
    @Binding var endDate: Date?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: ApeSpacing.lg) {
            HStack {
                Text("Rest Timer")
                    .font(.apeTitle)
                    .foregroundStyle(ApeColor.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(ApeColor.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(ApeColor.control)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .accessibilityLabel("Close rest timer")
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: ApeSpacing.lg) {
                    adjustmentButton(title: "−15", seconds: -15)

                    Text(countdown(at: context.date))
                        .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(ApeColor.textPrimary)
                        .frame(minWidth: 112)
                        .accessibilityLabel("Rest time remaining \(countdown(at: context.date))")

                    adjustmentButton(title: "+15", seconds: 15)
                }
            }
        }
        .padding(ApeSpacing.md)
        .background(ApeColor.primarySoft.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func adjustmentButton(title: String, seconds: Int) -> some View {
        Button(title) { adjust(by: seconds) }
            .font(.apeHeadline)
            .foregroundStyle(ApeColor.textPrimary)
            .frame(width: 58, height: 48)
            .background(ApeColor.control)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel(seconds > 0 ? "Add 15 seconds" : "Remove 15 seconds")
    }

    private func countdown(at date: Date) -> String {
        let seconds = max(0, Int(ceil((endDate ?? date).timeIntervalSince(date))))
        return ActiveWorkoutView.timerText(seconds: seconds)
    }

    private func adjust(by seconds: Int) {
        let currentEnd = endDate ?? Date()
        endDate = max(currentEnd.addingTimeInterval(TimeInterval(seconds)), Date())
    }
}

private struct ActiveWorkoutSet: Identifiable {
    let id = UUID()
    var number: Int
    var reps: Int
    var timeText: String
    var distance: Decimal
    var weight: Decimal
    var isCompleted = false
    var completedAt: Date?

    var timeSeconds: Double {
        let components = timeText.split(separator: ":", omittingEmptySubsequences: false)
        if components.count == 2,
           let minutes = Int(components[0]),
           let seconds = Int(components[1]) {
            return Double(max(0, minutes * 60 + min(seconds, 59)))
        }
        return Double(max(0, Int(timeText) ?? 0))
    }

    init(_ set: WorkoutPreviewSet) {
        number = set.number
        reps = set.reps
        let totalSeconds = max(0, Int(set.timeSeconds.rounded()))
        timeText = String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
        distance = set.distance
        weight = set.weight
    }


    init(_ set: WorkoutPreviewSet, isCompleted: Bool, completedAt: Date?) {
        number = set.number
        reps = set.reps
        let totalSeconds = max(0, Int(set.timeSeconds.rounded()))
        timeText = String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
        distance = set.distance
        weight = set.weight
        self.isCompleted = isCompleted
        self.completedAt = completedAt
    }

    init(number: Int) {
        self.number = number
        reps = 0
        timeText = "0:00"
        distance = 0
        weight = 0
    }
}

private struct TimeSetTarget: Identifiable {
    var id: String { "\(exerciseID)-\(setID)" }
    let exerciseID: UUID
    let setID: UUID
}

private struct SetTimePickerView: View {
    @Binding var minutes: Int
    @Binding var seconds: Int
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: ApeSpacing.sm) {
            HStack {
                Text("Set Time")
                    .font(.apeTitle)
                    .foregroundStyle(ApeColor.textPrimary)
                Spacer()
                Button("Done") {
                    onDone()
                    dismiss()
                }
                .font(.apeHeadline)
            }

            HStack(spacing: 0) {
                Picker("Minutes", selection: $minutes) {
                    ForEach(0...99, id: \.self) { value in
                        Text("\(value) min").tag(value)
                    }
                }
                .pickerStyle(.wheel)

                Picker("Seconds", selection: $seconds) {
                    ForEach(0...59, id: \.self) { value in
                        Text("\(value) sec").tag(value)
                    }
                }
                .pickerStyle(.wheel)
            }
            .frame(height: 190)
        }
        .padding(ApeSpacing.md)
        .background(ApeColor.surface.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

private struct ActiveExercisePicker: View {
    let exercises: [ExerciseListItem]
    let onSelect: (ExerciseListItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List(filteredExercises) { exercise in
                Button {
                    onSelect(exercise)
                    dismiss()
                } label: {
                    HStack(spacing: ApeSpacing.sm) {
                        Circle().fill(Color(hex: exercise.primaryMuscleColorHex)).frame(width: 14, height: 14)
                        Text(exercise.name).foregroundStyle(ApeColor.textPrimary)
                    }
                }
                .listRowBackground(ApeColor.surface)
            }
            .scrollContentBackground(.hidden)
            .background(ApeColor.background)
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var filteredExercises: [ExerciseListItem] {
        guard !searchText.isEmpty else { return exercises }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}
