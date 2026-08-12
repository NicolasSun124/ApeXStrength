import SwiftUI

struct WorkoutPreviewView: View {
    @StateObject private var viewModel: WorkoutPreviewViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingArchive = false
    @State private var isStartingWorkout = false
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

                Button("Start") { isStartingWorkout = true }
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
            if let workout = viewModel.workout {
                ActiveWorkoutView(workout: workout, repository: repository)
            }
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
        .task { if viewModel.state == .idle { viewModel.load() } }
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
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: ApeSpacing.xs) {
                                ForEach(workout.tags) { tag in
                                    previewTag(tag)
                                }
                            }
                        }
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
            }

            if exercise.sets.isEmpty {
                Text("No sets")
                    .font(.apeCallout)
                    .foregroundStyle(ApeColor.textSecondary)
            } else {
                HStack(spacing: ApeSpacing.xs) {
                    columnHeader("Set", width: 42)
                    columnHeader(performanceTitle(for: exercise.repType))
                    if exercise.difficultyType != .bodyweight {
                        columnHeader(exercise.difficultyType == .assistedWeight ? "Assisted" : "Weight")
                    }
                }

                ForEach(exercise.sets) { set in
                    HStack(spacing: ApeSpacing.xs) {
                        valueCell("\(set.number)", width: 42)
                        valueCell(performanceValue(set, repType: exercise.repType))
                        if exercise.difficultyType != .bodyweight {
                            valueCell(decimalText(set.weight))
                        }
                    }
                    .accessibilityElement(children: .combine)
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
        case .time: "Time (s)"
        case .distance: "Distance"
        }
    }

    private func performanceValue(_ set: WorkoutPreviewSet, repType: ExerciseRepType) -> String {
        switch repType {
        case .reps: "\(set.reps)"
        case .time: numberText(set.timeSeconds)
        case .distance: decimalText(set.distance)
        }
    }

    private func numberText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func decimalText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).doubleValue.formatted(.number.precision(.fractionLength(0...2)))
    }
}
