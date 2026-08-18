import SwiftUI

@MainActor
final class WorkoutSessionHistoryViewModel: ObservableObject {
    @Published private(set) var state: ViewLoadState = .idle
    @Published private(set) var sessions: [WorkoutSessionHistoryItem] = []
    private let repository: any WorkoutRepository

    init(repository: any WorkoutRepository) { self.repository = repository }

    func load() {
        state = .loading
        do {
            sessions = try repository.fetchSessionHistory()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct WorkoutSessionHistoryView: View {
    @StateObject private var viewModel: WorkoutSessionHistoryViewModel

    init(repository: any WorkoutRepository) {
        _viewModel = StateObject(wrappedValue: WorkoutSessionHistoryViewModel(repository: repository))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ApeLoadingView(title: "Loading session history")
            case .failed(let message):
                ApeErrorState(message: message, retry: viewModel.load)
            case .loaded where viewModel.sessions.isEmpty:
                ApeEmptyState(
                    icon: "list.bullet.clipboard",
                    title: "No sessions yet",
                    message: "Completed workouts will appear here."
                )
            case .loaded:
                ScrollView {
                    LazyVStack(spacing: ApeSpacing.sm) {
                        ForEach(viewModel.sessions) { session in
                            NavigationLink { WorkoutSessionDetailView(session: session) } label: {
                                sessionCard(session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(ApeSpacing.md)
                }
                .refreshable { viewModel.load() }
            }
        }
        .background(ApeColor.background.ignoresSafeArea())
        .navigationTitle("Session History")
        .navigationBarTitleDisplayMode(.inline)
        .task { if viewModel.state == .idle { viewModel.load() } }
    }

    private func sessionCard(_ session: WorkoutSessionHistoryItem) -> some View {
        ApeCard {
            HStack(spacing: ApeSpacing.sm) {
                VStack(alignment: .leading, spacing: ApeSpacing.xxs) {
                    Text(session.workoutName).font(.apeHeadline)
                    Text(session.endedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.apeCallout).foregroundStyle(ApeColor.textSecondary)
                    Text("\(session.exercises.count) exercises • \(duration(session.durationSeconds))")
                        .font(.apeCaption).foregroundStyle(ApeColor.textSecondary)
                }
                Spacer()
                if session.rating > 0 {
                    Label("\(session.rating)", systemImage: "star.fill")
                        .font(.apeCallout).foregroundStyle(ApeColor.primary)
                }
                Image(systemName: "chevron.right").foregroundStyle(ApeColor.textSecondary)
            }
            .foregroundStyle(ApeColor.textPrimary)
        }
    }
}

struct WorkoutSessionDetailView: View {
    let session: WorkoutSessionHistoryItem
    private let weightUnit = WeightUnit(setting: UserDefaultsSettingsService().load().weightUnit)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ApeSpacing.md) {
                sectionTitle("Details")
                detailsCard

                if !session.exercises.isEmpty {
                    sectionTitle("Exercises")
                    ForEach(session.exercises) { exercise in
                        exerciseCard(exercise)
                    }
                }
            }
            .padding(ApeSpacing.md)
        }
        .background(ApeColor.background.ignoresSafeArea())
        .navigationTitle(session.workoutName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var detailsCard: some View {
        ApeCard {
            VStack(spacing: ApeSpacing.sm) {
                detailRow("Date", session.endedAt.formatted(date: .long, time: .shortened))
                detailDivider
                detailRow("Duration", duration(session.durationSeconds))
                detailDivider
                detailRow("Completed", session.percentCompleted.formatted(.number.precision(.fractionLength(0))) + "%")
                detailDivider
                detailRow("Volume", decimal(session.volume) + " " + weightUnit.rawValue)
                if session.rating > 0 {
                    detailDivider
                    detailRow("Rating", "\(session.rating) / 5")
                }
                if let note = session.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    detailDivider
                    VStack(alignment: .leading, spacing: ApeSpacing.xxs) {
                        Text("Note").font(.apeBody).foregroundStyle(ApeColor.textPrimary)
                        Text(note).font(.apeBody).foregroundStyle(ApeColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func exerciseCard(_ exercise: WorkoutSessionHistoryExercise) -> some View {
        VStack(alignment: .leading, spacing: ApeSpacing.sm) {
            HStack(spacing: ApeSpacing.sm) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: exercise.primaryMuscleColorHex))
                    .frame(width: 38, height: 38)
                Text(exercise.name)
                    .font(.apeHeadline)
                    .foregroundStyle(ApeColor.textPrimary)
                Spacer()
            }

            HStack(spacing: ApeSpacing.xs) {
                columnHeader("Set", width: 42)
                columnHeader(performanceTitle(exercise.repType))
                columnHeader(exercise.difficultyType == .assistedWeight ? "Assisted" : "Weight")
                columnHeader("Done", width: 42)
            }

            ForEach(exercise.sets, id: \.number) { set in
                HStack(spacing: ApeSpacing.xs) {
                    readOnlyValue("\(set.number)", width: 42)
                    readOnlyValue(performanceValue(set, repType: exercise.repType))
                    readOnlyValue(exercise.difficultyType == .bodyweight ? "–" : decimal(set.weight))
                    Image(systemName: set.completed ? "checkmark" : "xmark")
                        .font(.apeHeadline)
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(set.completed ? ApeColor.success : ApeColor.control)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel(set.completed ? "Completed" : "Not completed")
                }
            }
        }
        .padding(ApeSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ApeColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: ApeRadius.card))
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(ApeColor.textSecondary) }
            .font(.apeBody).foregroundStyle(ApeColor.textPrimary)
    }

    private var detailDivider: some View {
        Divider().overlay(ApeColor.divider.opacity(0.35))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.apeTitle)
            .foregroundStyle(ApeColor.textPrimary)
    }

    private func columnHeader(_ title: String, width: CGFloat? = nil) -> some View {
        Text(title)
            .font(.apeCaption)
            .foregroundStyle(ApeColor.textSecondary)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width, alignment: .center)
    }

    private func readOnlyValue(_ text: String, width: CGFloat? = nil) -> some View {
        Text(text)
            .font(.apeBody)
            .foregroundStyle(ApeColor.textPrimary)
            .frame(maxWidth: width == nil ? .infinity : nil, minHeight: 42)
            .frame(width: width)
            .background(ApeColor.control)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func performanceTitle(_ repType: ExerciseRepType) -> String {
        switch repType {
        case .reps: "Reps"
        case .time: "Time"
        case .distance: "Distance"
        }
    }

    private func performanceValue(_ set: CompletedSessionSet, repType: ExerciseRepType) -> String {
        switch repType {
        case .reps: "\(set.reps)"
        case .time: duration(Int(set.timeSeconds))
        case .distance: decimal(set.distance)
        }
    }
}

private func duration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let remainingSeconds = seconds % 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    if minutes > 0 { return "\(minutes)m \(remainingSeconds)s" }
    return "\(remainingSeconds)s"
}

private func decimal(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).doubleValue.formatted(.number.precision(.fractionLength(0...2)))
}
