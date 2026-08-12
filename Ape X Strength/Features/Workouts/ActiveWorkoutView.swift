import CoreData
import SwiftUI

struct ActiveWorkoutView: View {
    let workout: WorkoutPreview
    private let repository: any WorkoutRepository
    @State private var exercises: [ActiveWorkoutExercise]
    @State private var availableExercises: [ExerciseListItem] = []
    @State private var isSelectingExercise = false
    @State private var startedAt = Date()
    @State private var restTimerEnd: Date?
    @State private var isRestTimerPresented = false

    init(workout: WorkoutPreview, repository: any WorkoutRepository) {
        self.workout = workout
        self.repository = repository
        _exercises = State(initialValue: workout.exercises.map(ActiveWorkoutExercise.init))
        _startedAt = State(initialValue: Date())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: ApeSpacing.md) {
                sessionControls

                ForEach($exercises) { $exercise in
                    exerciseCard(exercise: $exercise)
                }

                Button { isSelectingExercise = true } label: {
                    Label("Add Exercise", systemImage: "plus")
                }
                .buttonStyle(ApeSecondaryButtonStyle())
            }
            .padding(ApeSpacing.md)
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
        }
        .sheet(isPresented: $isSelectingExercise) {
            ActiveExercisePicker(
                exercises: availableExercises.filter { candidate in
                    !exercises.contains { $0.exerciseID == candidate.id }
                },
                onSelect: addExercise
            )
        }
        .sheet(isPresented: $isRestTimerPresented) {
            RestTimerView(endDate: $restTimerEnd)
                .presentationDetents([.height(230)])
                .presentationDragIndicator(.visible)
                .presentationBackground(ApeColor.primarySoft)
        }
        .task { loadAvailableExercises() }
        .task(id: restTimerEnd) { await clearRestTimerWhenFinished() }
    }

    private var sessionControls: some View {
        HStack(spacing: ApeSpacing.sm) {
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                Label(elapsedTime(at: context.date), systemImage: "timer")
                    .font(.apeHeadline.monospacedDigit())
                    .foregroundStyle(ApeColor.textPrimary)
                    .accessibilityLabel("Workout time \(elapsedTime(at: context.date))")
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

            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .foregroundStyle(ApeColor.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(ApeColor.control)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityLabel("Workout options")

            Button("Finish", action: {})
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
            }

            HStack(spacing: ApeSpacing.xs) {
                header("Set", width: 42)
                header(performanceTitle(exercise.wrappedValue.repType))
                if exercise.wrappedValue.difficultyType != .bodyweight {
                    header(exercise.wrappedValue.difficultyType == .assistedWeight ? "Assisted" : "Weight")
                }
                header("Done", width: 42)
            }

            ForEach(exercise.sets) { $set in
                HStack(spacing: ApeSpacing.xs) {
                    value("\(set.number)", width: 42)
                    if exercise.wrappedValue.repType == .reps {
                        editableInteger($set.reps, accessibilityLabel: "Reps for set \(set.number)")
                    } else {
                        value(performanceValue(set, repType: exercise.wrappedValue.repType))
                    }
                    if exercise.wrappedValue.difficultyType != .bodyweight {
                        editableDecimal($set.weight, accessibilityLabel: "Weight for set \(set.number)")
                    }
                    Button {
                        let isFinishing = !set.isCompleted
                        set.isCompleted.toggle()
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
        let delay = max(0, scheduledEnd.timeIntervalSinceNow)
        do {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        } catch {
            return
        }
        guard restTimerEnd == scheduledEnd else { return }

        restTimerEnd = nil
        isRestTimerPresented = false
        // TODO: Send a push notification when the rest timer finishes.
    }

    fileprivate static func timerText(seconds: Int) -> String {
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
            .multilineTextAlignment(.center)
            .font(.apeBody)
            .foregroundStyle(ApeColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(ApeColor.control)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(accessibilityLabel)
    }

    private func performanceTitle(_ type: ExerciseRepType) -> String {
        switch type { case .reps: "Reps"; case .time: "Time (s)"; case .distance: "Distance" }
    }

    private func performanceValue(_ set: ActiveWorkoutSet, repType: ExerciseRepType) -> String {
        switch repType {
        case .reps: "\(set.reps)"
        case .time: set.timeSeconds.formatted(.number.precision(.fractionLength(0...2)))
        case .distance: decimalText(set.distance)
        }
    }

    private func decimalText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).doubleValue.formatted(.number.precision(.fractionLength(0...2)))
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

    init(_ exercise: WorkoutPreviewExercise) {
        exerciseID = exercise.id
        name = exercise.name
        primaryMuscleColorHex = exercise.primaryMuscleColorHex
        repType = exercise.repType
        difficultyType = exercise.difficultyType
        targetRestSeconds = exercise.targetRestSeconds
        sets = exercise.sets.map(ActiveWorkoutSet.init)
    }

    init(exercise: ExerciseListItem) {
        exerciseID = exercise.id
        name = exercise.name
        primaryMuscleColorHex = exercise.primaryMuscleColorHex
        repType = exercise.repType
        difficultyType = exercise.difficultyType
        targetRestSeconds = exercise.targetRestSeconds
        sets = []
    }

    mutating func addSet() {
        sets.append(ActiveWorkoutSet(number: sets.count + 1))
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
    let number: Int
    var reps: Int
    let timeSeconds: Double
    let distance: Decimal
    var weight: Decimal
    var isCompleted = false

    init(_ set: WorkoutPreviewSet) {
        number = set.number
        reps = set.reps
        timeSeconds = set.timeSeconds
        distance = set.distance
        weight = set.weight
    }

    init(number: Int) {
        self.number = number
        reps = 0
        timeSeconds = 0
        distance = 0
        weight = 0
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
