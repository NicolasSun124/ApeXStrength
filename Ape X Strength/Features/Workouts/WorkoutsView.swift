import SwiftUI

struct WorkoutsView: View {
    @StateObject private var viewModel: WorkoutsViewModel
    @State private var isCreatingWorkout = false
    @State private var isShowingSessionHistory = false
    @State private var isShowingDraftPrompt = false
    @State private var isResumingSession = false
    @State private var searchText = ""
    private let repository: any WorkoutRepository

    init(viewModel: @autoclosure @escaping () -> WorkoutsViewModel, repository: any WorkoutRepository) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.repository = repository
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
                        action: { isCreatingWorkout = true }
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
            .searchable(text: $searchText, prompt: "Search workouts")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: { isShowingSessionHistory = true }) { Image(systemName: "list.bullet") }
                        .accessibilityLabel("Session history")
                    Button(action: { isCreatingWorkout = true }) { Image(systemName: "plus") }
                        .accessibilityLabel("Create workout")
                }
            }
            .navigationDestination(isPresented: $isShowingSessionHistory) {
                WorkoutSessionHistoryView(repository: repository)
            }
            .navigationDestination(isPresented: $isCreatingWorkout) {
                CreateWorkoutView(viewModel: CreateWorkoutViewModel(repository: repository)) {
                    viewModel.didCreateWorkout()
                }
            }
            .navigationDestination(isPresented: $isResumingSession) {
                if let draft = viewModel.activeSessionDraft {
                    ActiveWorkoutView(
                        draft: draft,
                        repository: repository,
                        onSessionSaved: {
                            isResumingSession = false
                            viewModel.clearActiveSessionDraft()
                            viewModel.load()
                        }
                    )
                }
            }
        }
        .confirmationDialog(
            "Resume active session?",
            isPresented: $isShowingDraftPrompt,
            titleVisibility: .visible
        ) {
            Button("Resume") { isResumingSession = true }
            Button("Discard", role: .destructive) { viewModel.discardActiveSessionDraft() }
        } message: {
            Text("An unfinished \(viewModel.activeSessionDraft?.workout.name ?? "workout") session was found.")
        }
        .alert(
            "Couldn’t Load Session",
            isPresented: Binding(
                get: { viewModel.draftErrorMessage != nil },
                set: { if !$0 { viewModel.dismissDraftError() } }
            )
        ) {
            Button("OK") { viewModel.dismissDraftError() }
        } message: {
            Text(viewModel.draftErrorMessage ?? "Please try again.")
        }
        .task {
            if viewModel.state == .idle { viewModel.load() }
            viewModel.detectActiveSessionDraft()
            isShowingDraftPrompt = viewModel.activeSessionDraft != nil
        }
    }

    private var workoutList: some View {
        ScrollView {
            LazyVStack(spacing: ApeSpacing.sm) {
                ForEach(filteredWorkouts) { workout in
                    NavigationLink {
                        WorkoutPreviewView(
                            viewModel: WorkoutPreviewViewModel(workoutID: workout.id, repository: repository),
                            repository: repository,
                            onArchived: viewModel.load
                        )
                    } label: {
                        WorkoutCollectionCard(workout: workout)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("workout-card-\(workout.name)")
                }
            }
            .padding(ApeSpacing.md)
        }
        .refreshable { viewModel.load() }
    }

    private var filteredWorkouts: [WorkoutListItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.workouts }
        return viewModel.workouts.filter { workout in
            workout.name.localizedCaseInsensitiveContains(query) ||
                workout.tags.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
    }
}

private struct WorkoutCollectionCard: View {
    let workout: WorkoutListItem
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: ApeSpacing.sm) {
            HStack(alignment: .top, spacing: ApeSpacing.sm) {
                VStack(alignment: .leading, spacing: ApeSpacing.xxs) {
                    Text(workout.name)
                        .font(.apeTitle)
                        .foregroundStyle(ApeColor.textPrimary)
                        .lineLimit(1)
                    tagGrid
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                metricTile(icon: "list.clipboard.fill", value: "\(workout.exerciseCount)", label: "Exercises")
                metricTile(icon: "stopwatch.fill", value: durationValue, label: "Minutes")
            }

            Rectangle()
                .fill(ApeColor.textSecondary)
                .frame(height: 3)

            Button { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } } label: {
                HStack {
                    Text("Statistics").font(.apeHeadline)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.apeHeadline)
                }
                .foregroundStyle(ApeColor.textPrimary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded { statistics }
        }
        .padding(ApeSpacing.sm)
        .background(ApeColor.elevated)
        .clipShape(RoundedRectangle(cornerRadius: ApeRadius.card))
    }

    private var displayedTags: [WorkoutTagSummary] {
        if workout.tags.count <= 4 { return workout.tags }
        return Array(workout.tags.prefix(3))
    }

    private var tagGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 3) {
            ForEach(displayedTags) { tag in tagChip(tag) }
            if workout.tags.count > 4 {
                Text("+\(workout.tags.count - 3) more")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(ApeColor.textPrimary)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                    .background(ApeColor.textSecondary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func tagChip(_ tag: WorkoutTagSummary) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(red: tag.color.red, green: tag.color.green, blue: tag.color.blue))
                .frame(width: 9, height: 9)
            Text(tag.name)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(ApeColor.textPrimary)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
        .background(ApeColor.control)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func metricTile(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 24))
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.apeTitle)
                Text(label).font(.apeCaption)
            }
        }
        .foregroundStyle(ApeColor.textPrimary)
        .frame(width: 96, height: 68)
        .background(ApeColor.control)
        .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control))
    }

    private var durationValue: String {
        guard let duration = workout.statistics.meanDurationMinutes else { return "–" }
        return duration.formatted(.number.precision(.fractionLength(0)))
    }

    private var statistics: some View {
        VStack(spacing: 0) {
            statisticRow("Last Used", value: workout.statistics.lastUsed?.formatted(date: .abbreviated, time: .shortened) ?? "–")
            statisticRow("Mean Duration", value: formatted(workout.statistics.meanDurationMinutes, suffix: " min"))
            statisticRow("Mean Volume", value: workout.statistics.meanVolume.map {
                let value = NSDecimalNumber(decimal: $0).doubleValue.formatted(
                    .number.precision(.fractionLength(0...2))
                )
                return "\(value) \(WeightUnit(setting: UserDefaultsSettingsService().load().weightUnit).rawValue)"
            } ?? "–")
            statisticRow("Mean Completed", value: formatted(workout.statistics.meanPercentCompleted, suffix: "%"), showsDivider: false)
        }
    }

    private func statisticRow(_ title: String, value: String, showsDivider: Bool = true) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                Spacer()
                Text(value)
            }
            .font(.apeBody)
            .foregroundStyle(ApeColor.textPrimary)
            .padding(.vertical, ApeSpacing.sm)
            if showsDivider { Divider().overlay(ApeColor.divider.opacity(0.35)) }
        }
    }

    private func formatted(_ value: Double?, suffix: String) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(1))) + suffix
    }
}
