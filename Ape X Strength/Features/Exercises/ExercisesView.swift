import SwiftUI

struct ExercisesView: View {
    @StateObject private var viewModel: ExercisesViewModel

    init(viewModel: @autoclosure @escaping () -> ExercisesViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    ApeLoadingView(title: "Loading exercises")
                case .failed(let message):
                    ApeErrorState(message: message, retry: viewModel.load)
                case .loaded where viewModel.exercises.isEmpty:
                    ApeEmptyState(
                        icon: "figure.strengthtraining.traditional",
                        title: "No exercises yet",
                        message: "Your exercise library will appear here.",
                        actionTitle: "Add Exercise",
                        action: { }
                    )
                case .loaded:
                    exerciseList
                }
            }
            .background(ApeColor.background.ignoresSafeArea())
            .navigationTitle("Exercises")
            .toolbarBackground(ApeColor.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                Button(action: { }) { Image(systemName: "plus") }
                    .accessibilityLabel("Add exercise")
            }
        }
        .task { if viewModel.state == .idle { viewModel.load() } }
    }

    private var exerciseList: some View {
        ScrollView {
            LazyVStack(spacing: ApeSpacing.sm) {
                ForEach(viewModel.exercises) { exercise in
                    ApeCard {
                        HStack {
                            VStack(alignment: .leading, spacing: ApeSpacing.xs) {
                                Text(exercise.name).font(.apeHeadline).foregroundStyle(ApeColor.textPrimary)
                                HStack {
                                    ApeTag(title: exercise.trackingType.replacingOccurrences(of: "_", with: " "))
                                    Text("\(exercise.targetRestSeconds)s rest")
                                        .font(.apeCaption).foregroundStyle(ApeColor.textSecondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.apeCaption).foregroundStyle(ApeColor.textSecondary)
                        }
                    }
                }
            }
            .padding(ApeSpacing.md)
        }
        .refreshable { viewModel.load() }
    }
}
