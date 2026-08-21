import CoreData
import SwiftUI
import UIKit

struct WorkoutPreviewView: View {
    @StateObject private var viewModel: WorkoutPreviewViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingArchive = false
    @State private var isStartingWorkout = false
    @State private var startedSession: (id: NSManagedObjectID, startedAt: Date)?
    @State private var resumableDraft: WorkoutSessionDraft?
    @State private var sessionStartErrorMessage: String?
    @State private var isReorderingExercises = false
    @State private var exerciseChoosingAlternates: WorkoutPreviewExercise?
    @State private var isEditingWorkout = false
    private let repository: any WorkoutRepository
    private let onArchived: () -> Void

    init(
        viewModel: @autoclosure @escaping () -> WorkoutPreviewViewModel,
        repository: any WorkoutRepository,
        onArchived: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.repository = repository
        self.onArchived = onArchived
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ApeLoadingView(title: "Loading workout")
            case .failed(let message):
                ApeErrorState(message: message, retry: viewModel.load)
            case .loaded:
                if let workout = viewModel.workout {
                    preview(workout)
                }
            }
        }
        .background(ApeColor.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ApeColor.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Edit") { isEditingWorkout = true }
                    .accessibilityLabel("Edit workout")
                Menu {
                    Button("Delete Workout", systemImage: "trash", role: .destructive) {
                        isConfirmingArchive = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Workout options")
                .disabled(viewModel.isArchiving)

                Button(resumableDraft == nil ? "Start" : "Resume") { startSession() }
                    .font(.apeHeadline)
                    .foregroundStyle(ApeColor.background)
                    .padding(.horizontal, ApeSpacing.sm)
                    .frame(height: 34)
                    .background(ApeColor.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .accessibilityLabel("Start session")
            }
        }
        .navigationDestination(isPresented: $isStartingWorkout) {
            if let resumableDraft {
                ActiveWorkoutView(
                    draft: resumableDraft,
                    repository: repository,
                    onSessionSaved: sessionDidClose
                )
            } else if let workout = viewModel.workout, let startedSession {
                ActiveWorkoutView(
                    workout: workout,
                    sessionID: startedSession.id,
                    startedAt: startedSession.startedAt,
                    repository: repository,
                    onSessionSaved: sessionDidClose
                )
            }
        }
        .navigationDestination(isPresented: $isEditingWorkout) {
            if let workout = viewModel.workout {
                CreateWorkoutView(
                    viewModel: CreateWorkoutViewModel(repository: repository, editing: workout)
                ) {
                    viewModel.load()
                    onArchived()
                }
            }
        }
        .alert(
            "Couldn’t Start Session",
            isPresented: Binding(
                get: { sessionStartErrorMessage != nil },
                set: { if !$0 { sessionStartErrorMessage = nil } }
            )
        ) {
            Button("OK") { sessionStartErrorMessage = nil }
        } message: {
            Text(sessionStartErrorMessage ?? "Please try again.")
        }
        .confirmationDialog(
            "Delete this workout?",
            isPresented: $isConfirmingArchive,
            titleVisibility: .visible
        ) {
            Button("Delete Workout", role: .destructive) {
                if viewModel.archive() {
                    onArchived()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The workout will be removed from your workout list.")
        }
        .alert(
            "Couldn’t Delete Workout",
            isPresented: Binding(
                get: { viewModel.archiveErrorMessage != nil },
                set: { if !$0 { viewModel.dismissArchiveError() } }
            )
        ) {
            Button("OK") { viewModel.dismissArchiveError() }
        } message: {
            Text(viewModel.archiveErrorMessage ?? "Please try again.")
        }
        .alert(
            "Couldn’t Update Workout",
            isPresented: Binding(
                get: { viewModel.editErrorMessage != nil },
                set: { if !$0 { viewModel.dismissEditError() } }
            )
        ) {
            Button("OK") { viewModel.dismissEditError() }
        } message: {
            Text(viewModel.editErrorMessage ?? "Please try again.")
        }
        .sheet(isPresented: $isReorderingExercises) {
            if let workout = viewModel.workout {
                PreviewExerciseReorderView(exercises: workout.exercises) { exercises in
                    if viewModel.reorderExercises(exercises.map(\.id)) {
                        onArchived()
                    }
                }
            }
        }
        .sheet(item: $exerciseChoosingAlternates) { exercise in
            PreviewAlternateExercisePickerView(
                exercises: viewModel.availableExercises.filter { candidate in
                    candidate.id != exercise.id
                        && !(viewModel.workout?.exercises.contains(where: { $0.id == candidate.id }) ?? false)
                },
                selection: Set(exercise.alternates.map(\.id))
            ) { selection in
                if viewModel.setAlternateExercises(selection, for: exercise.id) {
                    onArchived()
                }
            }
        }
        .task {
            if viewModel.state == .idle { viewModel.load() }
            loadResumableDraft()
        }
        .onAppear { loadResumableDraft() }
    }

    private func startSession() {
        guard let workout = viewModel.workout else { return }
        if resumableDraft?.workout.id == workout.id {
            isStartingWorkout = true
            return
        }
        let startedAt = Date()
        do {
            let exercises = workout.exercises.map { exercise in
                CompletedSessionExercise(
                    exerciseID: exercise.id,
                    sets: exercise.sets.map { set in
                        CompletedSessionSet(
                            number: set.number,
                            reps: set.reps,
                            timeSeconds: set.timeSeconds,
                            distance: set.distance,
                            weight: set.weight,
                            completed: false
                        )
                    }
                )
            }
            let id = try repository.startSession(
                workoutID: workout.id,
                startedAt: startedAt,
                exercises: exercises
            )
            startedSession = (id, startedAt)
            resumableDraft = nil
            isStartingWorkout = true
        } catch {
            sessionStartErrorMessage = error.localizedDescription
        }
    }

    private func loadResumableDraft() {
        guard let workout = viewModel.workout else { return }
        do {
            let draft = try repository.fetchActiveSessionDraft()
            resumableDraft = draft?.workout.id == workout.id ? draft : nil
        } catch {
            sessionStartErrorMessage = error.localizedDescription
        }
    }

    private func sessionDidClose() {
        resumableDraft = nil
        startedSession = nil
        onArchived()
        isStartingWorkout = false
        DispatchQueue.main.async {
            dismiss()
        }
    }

    private func preview(_ workout: WorkoutPreview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ApeSpacing.lg) {
                VStack(alignment: .leading, spacing: ApeSpacing.sm) {
                    Text(workout.name)
                        .font(.apeLargeTitle)
                        .foregroundStyle(ApeColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !workout.tags.isEmpty {
                        PreviewTagOverflowRow(tags: workout.tags)
                        .accessibilityLabel("Workout tags")
                    }
                }

                LazyVStack(spacing: ApeSpacing.md) {
                    ForEach(workout.exercises) { exercise in
                        exerciseCard(exercise)
                    }
                }
            }
            .padding(ApeSpacing.md)
        }
    }

    private func previewTag(_ tag: WorkoutTagSummary) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(red: tag.color.red, green: tag.color.green, blue: tag.color.blue))
                .frame(width: 12, height: 12)
            Text(tag.name)
                .font(.apeCallout)
                .foregroundStyle(ApeColor.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, ApeSpacing.sm)
        .frame(height: 30)
        .background(ApeColor.control)
        .clipShape(Capsule())
    }

    private func exerciseCard(_ exercise: WorkoutPreviewExercise) -> some View {
        VStack(alignment: .leading, spacing: ApeSpacing.sm) {
            HStack(spacing: ApeSpacing.sm) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: exercise.primaryMuscleColorHex))
                    .frame(width: 38, height: 38)

                Text(exercise.name)
                    .font(.apeHeadline)
                    .foregroundStyle(ApeColor.textPrimary)
                Spacer()
                if !exercise.alternates.isEmpty {
                    Menu {
                        ForEach(exercise.alternates) { alternate in
                            Button {
                                if viewModel.replaceExercise(exercise.id, with: alternate.id) {
                                    onArchived()
                                }
                            } label: {
                                Label(alternate.name, systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(ApeColor.textPrimary)
                            .padding()
                    }
                    .accessibilityLabel("Show alternates for \(exercise.name)")
                }
                Menu {
                    Button("Alternate Exercises", systemImage: "arrow.triangle.2.circlepath") {
                        exerciseChoosingAlternates = exercise
                    }
                    Button("Reorder", systemImage: "arrow.up.arrow.down") {
                        isReorderingExercises = true
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        if viewModel.removeExercise(id: exercise.id) {
                            onArchived()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(ApeColor.textPrimary)
                        .padding()
                }
                .accessibilityLabel("Options for \(exercise.name)")
            }

            if exercise.sets.isEmpty {
                Text("No sets")
                    .font(.apeCallout)
                    .foregroundStyle(ApeColor.textSecondary)
            } else {
                HStack(spacing: ApeSpacing.xs) {
                    columnHeader("Set", width: 42)
                    columnHeader(performanceTitle(for: exercise.repType))
                    columnHeader(exercise.difficultyType == .assistedWeight ? "Assisted" : "Weight")
                }

                ForEach(exercise.sets) { set in
                    SetSwipeToRemove {
                        if viewModel.removeSet(number: set.number, from: exercise.id) {
                            onArchived()
                        }
                    } content: {
                        HStack(spacing: ApeSpacing.xs) {
                            valueCell("\(set.number)", width: 42)
                            valueCell(performanceValue(set, repType: exercise.repType))
                            if exercise.difficultyType == .bodyweight {
                                valueCell("—")
                            } else {
                                valueCell(decimalText(set.weight))
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAction(named: "Remove set \(set.number)") {
                        if viewModel.removeSet(number: set.number, from: exercise.id) { onArchived() }
                    }
                }
            }
        }
        .padding(ApeSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ApeColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: ApeRadius.card))
    }

    private func columnHeader(_ title: String, width: CGFloat? = nil) -> some View {
        Text(title)
            .font(.apeCaption)
            .foregroundStyle(ApeColor.textSecondary)
            .frame(maxWidth: width == nil ? .infinity : nil, minHeight: 20)
            .frame(width: width)
    }

    private func valueCell(_ value: String, width: CGFloat? = nil) -> some View {
        Text(value)
            .font(.apeBody)
            .foregroundStyle(ApeColor.textPrimary)
            .frame(maxWidth: width == nil ? .infinity : nil, minHeight: 38)
            .frame(width: width)
            .background(ApeColor.control)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func performanceTitle(for repType: ExerciseRepType) -> String {
        switch repType {
        case .reps: "Reps"
        case .time: "Time"
        case .distance: "Distance"
        }
    }

    private func performanceValue(_ set: WorkoutPreviewSet, repType: ExerciseRepType) -> String {
        switch repType {
        case .reps: "\(set.reps)"
        case .time: formattedTime(set.timeSeconds)
        case .distance: decimalText(set.distance)
        }
    }

    private func formattedTime(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func decimalText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).doubleValue.formatted(.number.precision(.fractionLength(0...2)))
    }
}

private struct PreviewTagOverflowRow: View {
    let tags: [WorkoutTagSummary]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tagRow(visibleCount: tags.count)
            ForEach(Array(stride(from: tags.count - 1, through: 0, by: -1)), id: \.self) { count in
                tagRow(visibleCount: count)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tagRow(visibleCount: Int) -> some View {
        HStack(spacing: ApeSpacing.xs) {
            ForEach(Array(tags.prefix(visibleCount))) { tag in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: tag.color.red, green: tag.color.green, blue: tag.color.blue))
                        .frame(width: 12, height: 12)
                    Text(tag.name)
                        .font(.apeCallout)
                        .foregroundStyle(ApeColor.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, ApeSpacing.sm)
                .frame(height: 30)
                .background(ApeColor.control)
                .clipShape(Capsule())
            }
            if visibleCount < tags.count {
                Text("+\(tags.count - visibleCount) more")
                    .font(.apeCallout)
                    .foregroundStyle(ApeColor.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, ApeSpacing.sm)
                    .frame(height: 30)
                    .background(ApeColor.textSecondary.opacity(0.55))
                    .clipShape(Capsule())
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct SetSwipeToRemove<Content: View>: View {
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
                Image(systemName: "trash.fill").foregroundStyle(.white).frame(width: 62, height: 38)
            }
            .background(ApeColor.destructive)
            .opacity(offset < 0 ? 1 : 0)

            content
                .offset(x: offset)
                .contentShape(Rectangle())
                .simultaneousGesture(
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

private struct PreviewAlternateExercisePickerView: View {
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
                        Text(exercise.name)
                            .font(.apeHeadline)
                            .foregroundStyle(ApeColor.textPrimary)
                        Spacer()
                        if pending.contains(exercise.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(ApeColor.primary)
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(pending)
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var filteredExercises: [ExerciseListItem] {
        searchText.isEmpty ? exercises : exercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}

private struct PreviewExerciseReorderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var exercises: [WorkoutPreviewExercise]
    let onFinish: ([WorkoutPreviewExercise]) -> Void

    init(exercises: [WorkoutPreviewExercise], onFinish: @escaping ([WorkoutPreviewExercise]) -> Void) {
        _exercises = State(initialValue: exercises)
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            PreviewExerciseReorderTable(exercises: $exercises)
                .background(ApeColor.background)
                .navigationTitle("Reorder Exercises")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Finish") {
                            onFinish(exercises)
                            dismiss()
                        }
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}

private struct PreviewExerciseReorderTable: UIViewControllerRepresentable {
    @Binding var exercises: [WorkoutPreviewExercise]

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
        var exercises: Binding<[WorkoutPreviewExercise]>
        var displayedIDs: [NSManagedObjectID]

        init(exercises: Binding<[WorkoutPreviewExercise]>) {
            self.exercises = exercises
            displayedIDs = exercises.wrappedValue.map(\.id)
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            exercises.wrappedValue.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let identifier = "PreviewExerciseReorderCell"
            let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
                ?? UITableViewCell(style: .default, reuseIdentifier: identifier)
            let exercise = exercises.wrappedValue[indexPath.row]
            var content = cell.defaultContentConfiguration()
            content.image = UIImage(systemName: "circle.fill")
            content.imageProperties.tintColor = UIColor(Color(hex: exercise.primaryMuscleColorHex))
            content.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18)
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
