import SwiftUI

struct ExerciseDetailView: View {
    @StateObject private var viewModel: ExerciseDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var confirmsArchive = false
    private let repository: any ExerciseRepository
    private let onChanged: () -> Void

    init(
        viewModel: @autoclosure @escaping () -> ExerciseDetailViewModel,
        repository: any ExerciseRepository,
        onChanged: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.repository = repository
        self.onChanged = onChanged
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading: ApeLoadingView(title: "Loading exercise")
            case .failed(let message): ApeErrorState(message: message, retry: viewModel.load)
            case .loaded:
                if let exercise = viewModel.exercise { detail(exercise) }
            }
        }
        .background(ApeColor.background.ignoresSafeArea())
        .navigationTitle(viewModel.exercise?.name ?? "Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(viewModel.exercise?.isGlobal == true ? "Copy & Edit" : "Edit", systemImage: "pencil") {
                        isEditing = true
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmsArchive = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            CreateExerciseView(
                viewModel: CreateExerciseViewModel(repository: repository, exerciseID: viewModel.exercise?.id)
            ) { savedExerciseID in
                viewModel.showExercise(id: savedExerciseID)
                onChanged()
            }
        }
        .confirmationDialog("Archive this exercise?", isPresented: $confirmsArchive, titleVisibility: .visible) {
            Button("Archive Exercise", role: .destructive) {
                if viewModel.archive() { onChanged(); dismiss() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The exercise can be restored later from Archived Exercises.")
        }
        .task { if viewModel.state == .idle { viewModel.load() } }
    }

    private func detail(_ exercise: ExerciseDetail) -> some View {
        ScrollView {
            VStack(spacing: ApeSpacing.sm) {
                configurationRow("Rep type", exercise.repType.title)
                configurationRow("Difficulty type", exercise.difficultyType.title)
                configurationRow("Default rest time", restLabel(exercise.targetRestSeconds).replacingOccurrences(of: " rest", with: ""))
                configurationRow("Primary muscle", exercise.primaryMuscle.name)
                configurationRow("Secondary muscles", exercise.secondaryMuscles.isEmpty ? "None" : exercise.secondaryMuscles.map(\.name).joined(separator: ", "))
            }
            .padding(ApeSpacing.md)
        }
    }

    private func configurationRow(_ title: String, _ value: String) -> some View {
        ApeCard {
            VStack(alignment: .leading, spacing: ApeSpacing.xs) {
                Text(title).font(.apeCaption).foregroundStyle(ApeColor.textSecondary)
                Text(value).font(.apeHeadline).foregroundStyle(ApeColor.textPrimary)
            }
        }
    }
}
