import CoreData
import SwiftUI

struct CreateWorkoutView: View {
    @StateObject private var viewModel: CreateWorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isSelectingExercises = false
    @State private var isSelectingTags = false
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
                RoundedRectangle(cornerRadius: ApeRadius.control)
                    .fill(ApeColor.primary)
                    .frame(width: 54, height: 54)
                    .overlay { Image(systemName: "dumbbell.fill").foregroundStyle(ApeColor.background) }
                VStack(alignment: .leading, spacing: ApeSpacing.xxs) {
                    Text(exercise.name).font(.apeHeadline).foregroundStyle(ApeColor.textPrimary)
                }
                Spacer()
                Menu {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        if let index = viewModel.selectedExercises.firstIndex(where: { $0.id == exercise.id }) {
                            viewModel.removeExercises(at: IndexSet(integer: index))
                        }
                    }
                } label: { Image(systemName: "ellipsis").foregroundStyle(ApeColor.textPrimary).padding() }
            }

            Button("Add Set") { }
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
                    HStack {
                        VStack(alignment: .leading) {
                            Text(exercise.name).foregroundStyle(ApeColor.textPrimary)
                            Text(exercise.repType.title + " • " + exercise.difficultyType.title)
                                .font(.apeCaption).foregroundStyle(ApeColor.textSecondary)
                        }
                        Spacer()
                        if pending.contains(exercise.id) || selected.contains(exercise.id) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(ApeColor.primary)
                        }
                    }
                }
                .disabled(selected.contains(exercise.id))
                .listRowBackground(ApeColor.surface)
            }
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
