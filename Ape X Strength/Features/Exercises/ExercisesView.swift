import SwiftUI

struct ExercisesView: View {
    @StateObject private var viewModel: ExercisesViewModel
    @State private var isCreatingExercise = false
    private let repository: any ExerciseRepository

    init(viewModel: @autoclosure @escaping () -> ExercisesViewModel, repository: any ExerciseRepository) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.repository = repository
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
                        message: "Create an exercise to start building your library.",
                        actionTitle: "Create Exercise",
                        action: { isCreatingExercise = true }
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
                Button("Create Exercise", systemImage: "plus") { isCreatingExercise = true }
                    .accessibilityLabel("Create exercise")
            }
            .sheet(isPresented: $isCreatingExercise) {
                CreateExerciseView(viewModel: CreateExerciseViewModel(repository: repository)) { _ in
                    viewModel.didCreateExercise()
                }
            }
        }
        .task { if viewModel.state == .idle { viewModel.load() } }
    }

    private var exerciseList: some View {
        ScrollView {
            LazyVStack(spacing: ApeSpacing.sm) {
                ForEach(viewModel.exercises) { exercise in
                    NavigationLink {
                        ExerciseDetailView(
                            viewModel: ExerciseDetailViewModel(id: exercise.id, repository: repository),
                            repository: repository,
                            onChanged: viewModel.load
                        )
                    } label: {
                        ApeCard {
                            HStack {
                                VStack(alignment: .leading, spacing: ApeSpacing.xs) {
                                    HStack(spacing: ApeSpacing.xs) {
                                        Circle()
                                            .fill(Color(hex: exercise.primaryMuscleColorHex))
                                            .frame(width: 14, height: 14)
                                        Text(exercise.name).font(.apeHeadline).foregroundStyle(ApeColor.textPrimary)
                                    }
                                    HStack {
                                        ApeTag(title: exercise.repType.title)
                                        ApeTag(title: exercise.difficultyType.title)
                                        Text(restLabel(exercise.targetRestSeconds))
                                            .font(.apeCaption).foregroundStyle(ApeColor.textSecondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.apeCaption).foregroundStyle(ApeColor.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(ApeSpacing.md)
        }
        .refreshable { viewModel.load() }
    }
}

func restLabel(_ seconds: Int) -> String {
    if seconds >= 60, seconds % 60 == 0 { return "\(seconds / 60) min rest" }
    return "\(seconds)s rest"
}
