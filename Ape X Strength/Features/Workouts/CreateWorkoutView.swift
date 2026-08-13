import CoreData
import SwiftUI
import UIKit

struct CreateWorkoutView: View {
    @StateObject private var viewModel: CreateWorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isSelectingExercises = false
    @State private var isSelectingTags = false
    @State private var isReorderingExercises = false
    @State private var exerciseChoosingAlternates: ExerciseListItem?
    @FocusState private var isNameFocused: Bool
    let onSaved: () -> Void

    init(viewModel: @autoclosure @escaping () -> CreateWorkoutViewModel, onSaved: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.onSaved = onSaved
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ApeSpacing.md) {
                TextField("New Workout", text: $viewModel.name)
                    .font(.apeLargeTitle)
                    .foregroundStyle(ApeColor.textPrimary)
                    .textInputAutocapitalization(.words)
                    .focused($isNameFocused)
                    .accessibilityLabel("Workout name")

                Button { isSelectingTags = true } label: {
                    VStack(alignment: .leading, spacing: ApeSpacing.xs) {
                        HStack {
                            Text("Tags").font(.apeHeadline)
                            Spacer()
                            Image(systemName: "plus").font(.title2)
                        }
                        if !displayedTags.isEmpty {
                            TagOverflowRow(tags: displayedTags)
                        }
                    }
                    .foregroundStyle(ApeColor.textPrimary)
                    .padding(ApeSpacing.md)
                    .background(ApeColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control))
                }
                .buttonStyle(.plain)

                ForEach(viewModel.selectedExercises) { exercise in
                    exerciseCard(exercise)
                }

                Button { isSelectingExercises = true } label: {
                    Label("Add Exercises", systemImage: "plus")
                }
                .buttonStyle(ApeSecondaryButtonStyle())

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).font(.apeCallout).foregroundStyle(ApeColor.destructive)
                }
            }
            .padding(ApeSpacing.md)
        }
        .background(ApeColor.background.ignoresSafeArea())
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ApeColor.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    if viewModel.save() { onSaved(); dismiss() }
                } label: { Image(systemName: "checkmark") }
                .disabled(!viewModel.isValid || viewModel.isSaving)
                .accessibilityLabel("Save workout")
            }
        }
        .sheet(isPresented: $isSelectingExercises) {
            ExercisePickerView(exercises: viewModel.exercises, selected: Set(viewModel.selectedExercises.map(\.id))) {
                viewModel.addExercises($0)
            }
        }
        .sheet(isPresented: $isSelectingTags) {
            TagPickerView(
                tags: viewModel.tags,
                selection: $viewModel.selectedTagIDs,
                onAdd: viewModel.addTag
            )
        }
        .sheet(isPresented: $isReorderingExercises) {
            ReorderExercisesView(exercises: viewModel.selectedExercises) {
                viewModel.reorderExercises($0)
            }
        }
        .sheet(item: $exerciseChoosingAlternates) { exercise in
            AlternateExercisePickerView(
                exercises: viewModel.exercises.filter { candidate in
                    candidate.id != exercise.id
                        && !viewModel.selectedExercises.contains(where: { $0.id == candidate.id })
                },
                selection: Binding(
                    get: { viewModel.alternateExerciseIDs[exercise.id] ?? [] },
                    set: { viewModel.alternateExerciseIDs[exercise.id] = $0 }
                )
            )
        }
        .task { viewModel.load() }
    }

    private var displayedTags: [(name: String, color: TagColor)] {
        let saved = viewModel.tags
            .filter { viewModel.selectedTagIDs.contains($0.id) }
            .map { (name: $0.name, color: $0.color) }
        return saved
    }

    private func exerciseCard(_ exercise: ExerciseListItem) -> some View {
        VStack(spacing: ApeSpacing.md) {
            HStack(spacing: ApeSpacing.md) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(ApeColor.primary)
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: ApeSpacing.xxs) {
                    Text(exercise.name).font(.apeHeadline).foregroundStyle(ApeColor.textPrimary)
                }
                Spacer()
                if !(viewModel.alternateExerciseIDs[exercise.id] ?? []).isEmpty {
                    Menu {
                        ForEach(alternateExercises(for: exercise)) { alternate in
                            Button {
                                viewModel.replaceExercise(exercise, with: alternate)
                            } label: {
                                Label {
                                    Text(alternate.name)
                                } icon: {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
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
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        if let index = viewModel.selectedExercises.firstIndex(where: { $0.id == exercise.id }) {
                            viewModel.removeExercises(at: IndexSet(integer: index))
                        }
                    }
                } label: { Image(systemName: "ellipsis").foregroundStyle(ApeColor.textPrimary).padding() }
            }

            ForEach(Array((viewModel.plannedSets[exercise.id] ?? []).enumerated()), id: \.element.id) { index, set in
                setRow(
                    number: index + 1,
                    set: viewModel.setBinding(for: exercise.id, setID: set.id),
                    exercise: exercise
                ) {
                    viewModel.removeSet(set.id, from: exercise.id)
                }
            }

            Button("Add Set") { viewModel.addSet(to: exercise.id) }
                .font(.apeBody)
                .foregroundStyle(ApeColor.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(ApeColor.control)
                .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control))
                .accessibilityLabel("Add set to \(exercise.name)")
        }
        .padding(ApeSpacing.md)
        .background(ApeColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: ApeRadius.card))
    }

    private func setRow(
        number: Int,
        set: Binding<WorkoutSetDraft>,
        exercise: ExerciseListItem,
        onRemove: @escaping () -> Void
    ) -> some View {
        SwipeToRemoveSet(action: onRemove) {
            HStack(spacing: ApeSpacing.xs) {
                Text("\(number)")
                    .font(.apeHeadline)
                    .foregroundStyle(ApeColor.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(ApeColor.control)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                TextField(performancePlaceholder(for: exercise.repType), text: set.performanceValue)
                    .keyboardType(exercise.repType == .reps ? .numberPad : .decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.apeBody)
                    .foregroundStyle(ApeColor.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(ApeColor.control)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if exercise.difficultyType == .bodyweight {
                    Text("—")
                        .font(.apeHeadline)
                        .foregroundStyle(ApeColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(ApeColor.control)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Bodyweight")
                } else {
                    TextField(weightPlaceholder(for: exercise.difficultyType), text: set.weightValue)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.apeBody)
                        .foregroundStyle(ApeColor.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(ApeColor.control)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .accessibilityAction(named: "Remove set \(number)", onRemove)
    }

    private func performancePlaceholder(for repType: ExerciseRepType) -> String {
        switch repType {
        case .reps: "Reps"
        case .time: "Time (s)"
        case .distance: "Distance"
        }
    }

    private func weightPlaceholder(for difficultyType: ExerciseDifficultyType) -> String {
        difficultyType == .assistedWeight ? "Assisted" : "Weight"
    }

    private func alternateExercises(for exercise: ExerciseListItem) -> [ExerciseListItem] {
        let ids = viewModel.alternateExerciseIDs[exercise.id] ?? []
        return viewModel.exercises.filter { ids.contains($0.id) }
    }
}

private struct AlternateExercisePickerView: View {
    let exercises: [ExerciseListItem]
    @Binding var selection: Set<NSManagedObjectID>
    @Environment(\.dismiss) private var dismiss
    @State private var pending: Set<NSManagedObjectID>
    @State private var searchText = ""

    init(exercises: [ExerciseListItem], selection: Binding<Set<NSManagedObjectID>>) {
        self.exercises = exercises
        _selection = selection
        _pending = State(initialValue: selection.wrappedValue)
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
                        selection = pending
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

private struct ReorderExercisesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var exercises: [ExerciseListItem]
    let onFinish: ([ExerciseListItem]) -> Void

    init(exercises: [ExerciseListItem], onFinish: @escaping ([ExerciseListItem]) -> Void) {
        _exercises = State(initialValue: exercises)
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            ExerciseReorderTable(exercises: $exercises)
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

private struct ExerciseReorderTable: UIViewControllerRepresentable {
    @Binding var exercises: [ExerciseListItem]

    func makeCoordinator() -> Coordinator {
        Coordinator(exercises: $exercises)
    }

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
        var exercises: Binding<[ExerciseListItem]>
        var displayedIDs: [NSManagedObjectID]

        init(exercises: Binding<[ExerciseListItem]>) {
            self.exercises = exercises
            displayedIDs = exercises.wrappedValue.map(\.id)
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            exercises.wrappedValue.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let reuseIdentifier = "ExerciseReorderCell"
            let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier)
                ?? UITableViewCell(style: .default, reuseIdentifier: reuseIdentifier)
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

        func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
            true
        }

        func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
            var reordered = exercises.wrappedValue
            let exercise = reordered.remove(at: sourceIndexPath.row)
            reordered.insert(exercise, at: destinationIndexPath.row)
            displayedIDs = reordered.map(\.id)
            exercises.wrappedValue = reordered
        }
    }
}

private struct SwipeToRemoveSet<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var offset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0

    init(action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive, action: action) {
                Image(systemName: "trash.fill")
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 38)
            }
            .background(ApeColor.destructive)

            content
                .offset(x: offset)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            offset = min(0, max(-140, dragStartOffset + value.translation.width))
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
                                dragStartOffset = offset < -32 ? -62 : 0
                            }
                        }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct WorkoutTagChip: View {
    let name: String
    let color: TagColor

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(red: color.red, green: color.green, blue: color.blue))
                .frame(width: 14, height: 14)
            Text(name)
                .font(.apeCallout)
                .foregroundStyle(ApeColor.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, ApeSpacing.xs)
        .frame(height: 26)
        .background(ApeColor.control)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct TagOverflowRow: View {
    let tags: [(name: String, color: TagColor)]

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
            ForEach(Array(tags.prefix(visibleCount)), id: \.name) { tag in
                WorkoutTagChip(name: tag.name, color: tag.color)
            }
            if visibleCount < tags.count {
                Text("+\(tags.count - visibleCount) more")
                    .font(.apeCallout)
                    .foregroundStyle(ApeColor.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, ApeSpacing.xs)
                    .frame(height: 26)
                    .background(ApeColor.textSecondary.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ExercisePickerView: View {
    let exercises: [ExerciseListItem]
    let selected: Set<NSManagedObjectID>
    let onDone: (Set<NSManagedObjectID>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pending: Set<NSManagedObjectID> = []
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List(filteredExercises) { exercise in
                Button {
                    if pending.contains(exercise.id) { pending.remove(exercise.id) } else { pending.insert(exercise.id) }
                } label: {
                    ApeCard {
                        HStack {
                            VStack(alignment: .leading, spacing: ApeSpacing.xs) {
                                HStack(spacing: ApeSpacing.xs) {
                                    Circle()
                                        .fill(Color(hex: exercise.primaryMuscleColorHex))
                                        .frame(width: 14, height: 14)
                                    Text(exercise.name)
                                        .font(.apeHeadline)
                                        .foregroundStyle(ApeColor.textPrimary)
                                }
                                HStack {
                                    ApeTag(title: exercise.repType.title)
                                    ApeTag(title: exercise.difficultyType.title)
                                    Text(restLabel(exercise.targetRestSeconds))
                                        .font(.apeCaption)
                                        .foregroundStyle(ApeColor.textSecondary)
                                }
                            }
                            Spacer()
                            if pending.contains(exercise.id) || selected.contains(exercise.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(ApeColor.primary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(selected.contains(exercise.id))
                .listRowInsets(EdgeInsets(top: 6, leading: ApeSpacing.md, bottom: 6, trailing: ApeSpacing.md))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(ApeColor.background)
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Add Exercises")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { onDone(pending); dismiss() }.disabled(pending.isEmpty) }
            }
        }.preferredColorScheme(.dark)
    }

    private var filteredExercises: [ExerciseListItem] {
        searchText.isEmpty ? exercises : exercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}

private struct TagPickerView: View {
    let tags: [TagItem]
    @Binding var selection: Set<NSManagedObjectID>
    let onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newTag = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Create a tag") {
                    HStack {
                        TextField("Tag name", text: $newTag).textInputAutocapitalization(.words)
                        Button("Add") { onAdd(newTag); newTag = "" }.disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section("Tags") {
                    ForEach(tags) { tag in
                        Button {
                            if selection.contains(tag.id) { selection.remove(tag.id) } else { selection.insert(tag.id) }
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(
                                        red: tag.color.red,
                                        green: tag.color.green,
                                        blue: tag.color.blue
                                    ))
                                    .frame(width: 18, height: 18)
                                Text(tag.name).foregroundStyle(ApeColor.textPrimary)
                                Spacer()
                                if selection.contains(tag.id) { Image(systemName: "checkmark").foregroundStyle(ApeColor.primary) }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ApeColor.background)
            .navigationTitle("Tags")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}
