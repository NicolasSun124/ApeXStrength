import SwiftUI

struct ExerciseDetailView: View {
    @StateObject private var viewModel: ExerciseDetailViewModel

    init(viewModel: @autoclosure @escaping () -> ExerciseDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
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
        .task { if viewModel.state == .idle { viewModel.load() } }
    }

    private func detail(_ exercise: ExerciseDetail) -> some View {
        ScrollView {
            VStack(spacing: ApeSpacing.sm) {
                configurationRow("Rep type", exercise.repType.title)
                configurationRow("Difficulty type", exercise.difficultyType.title)
                configurationRow("Default rest time", restLabel(exercise.targetRestSeconds).replacingOccurrences(of: " rest", with: ""))
                configurationRow("Primary muscle", exercise.primaryMuscle)
                configurationRow("Secondary muscles", exercise.secondaryMuscles.isEmpty ? "None" : exercise.secondaryMuscles.joined(separator: ", "))
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
