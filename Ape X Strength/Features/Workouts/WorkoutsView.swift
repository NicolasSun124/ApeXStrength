import SwiftUI

struct WorkoutsView: View {
    @StateObject private var viewModel: WorkoutsViewModel

    init(viewModel: @autoclosure @escaping () -> WorkoutsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    ApeLoadingView(title: "Loading workouts")
                case .failed(let message):
                    ApeErrorState(message: message, retry: viewModel.load)
                case .loaded where viewModel.workouts.isEmpty:
                    ApeEmptyState(
                        icon: "dumbbell.fill",
                        title: "Build your first workout",
                        message: "Create a reusable workout and add exercises and planned sets.",
                        actionTitle: "Create Workout",
                        action: { }
                    )
                case .loaded:
                    workoutList
                }
            }
            .background(ApeColor.background.ignoresSafeArea())
            .navigationTitle("Workouts")
            .toolbarBackground(ApeColor.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                Button(action: { }) { Image(systemName: "plus") }
                    .accessibilityLabel("Create workout")
            }
        }
        .task { if viewModel.state == .idle { viewModel.load() } }
    }

    private var workoutList: some View {
        ScrollView {
            LazyVStack(spacing: ApeSpacing.sm) {
                ForEach(viewModel.workouts) { workout in
                    ApeCard {
                        HStack(spacing: ApeSpacing.md) {
                            Image(systemName: "dumbbell.fill")
                                .foregroundStyle(ApeColor.textPrimary)
                                .frame(width: 44, height: 44)
                                .background(ApeColor.control)
                                .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control))
                            VStack(alignment: .leading, spacing: ApeSpacing.xxs) {
                                Text(workout.name).font(.apeHeadline).foregroundStyle(ApeColor.textPrimary)
                                Text("\(workout.exerciseCount) exercises")
                                    .font(.apeCallout).foregroundStyle(ApeColor.textSecondary)
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
