import SwiftUI

struct WorkoutFinishView: View {
    let workoutName: String
    let exerciseNames: [String]
    let onFinish: (_ shouldSave: Bool, _ rating: Int) -> String?
    @State private var rating = 3
    @State private var comparison: ImprovementComparison = .lifetime
    @State private var isConfirmingFinish = false
    @State private var saveErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ApeSpacing.lg) {
                ratingSection
                improvementsSection
            }
            .padding(ApeSpacing.md)
        }
        .background(ApeColor.background.ignoresSafeArea())
        .navigationTitle(workoutName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ApeColor.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { isConfirmingFinish = true } label: {
                    Image(systemName: "checkmark")
                        .font(.apeHeadline)
                }
                .accessibilityLabel("End workout")
            }
        }
        .confirmationDialog(
            "Finish this session?",
            isPresented: $isConfirmingFinish,
            titleVisibility: .visible
        ) {
            Button("Save Session") { finish(shouldSave: true) }
            Button("Don't Save", role: .destructive) { finish(shouldSave: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose whether to save this workout and update your history.")
        }
        .alert(
            "Couldn’t Save Session",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK") { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "Please try again.")
        }
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: ApeSpacing.sm) {
            Text("How was your workout?")
                .font(.apeTitle)
                .foregroundStyle(ApeColor.textPrimary)

            HStack(spacing: ApeSpacing.xs) {
                ForEach(Array(ratingEmojis.enumerated()), id: \.offset) { index, emoji in
                    Button {
                        rating = index + 1
                    } label: {
                        Text(emoji)
                            .font(.system(size: 30))
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(rating == index + 1 ? ApeColor.primarySoft : ApeColor.control.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control))
                            .overlay {
                                RoundedRectangle(cornerRadius: ApeRadius.control)
                                    .stroke(rating == index + 1 ? ApeColor.primary : .clear, lineWidth: 2)
                            }
                    }
                    .accessibilityLabel("Rating \(index + 1) of 5")
                    .accessibilityAddTraits(rating == index + 1 ? .isSelected : [])
                }
            }
        }
        .padding(ApeSpacing.md)
        .background(ApeColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: ApeRadius.card))
    }

    private var improvementsSection: some View {
        VStack(alignment: .leading, spacing: ApeSpacing.md) {
            HStack {
                Text("Improvements")
                    .font(.apeTitle)
                    .foregroundStyle(ApeColor.textPrimary)
                Spacer()
                Menu {
                    Picker("Comparison", selection: $comparison) {
                        ForEach(ImprovementComparison.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    HStack(spacing: ApeSpacing.xs) {
                        Text(comparison.title)
                        Image(systemName: "chevron.down")
                    }
                    .font(.apeCallout)
                    .foregroundStyle(ApeColor.textPrimary)
                    .padding(.horizontal, ApeSpacing.sm)
                    .frame(height: 36)
                    .background(ApeColor.control)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .accessibilityLabel("Improvement comparison: \(comparison.title)")
            }

            ForEach(Array(exerciseNames.enumerated()), id: \.offset) { _, exerciseName in
                exerciseImprovementCard(exerciseName)
            }
        }
    }

    private func exerciseImprovementCard(_ exerciseName: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(exerciseName)
                .font(.apeHeadline)
                .foregroundStyle(ApeColor.textPrimary)
                .padding(.bottom, ApeSpacing.xs)

            metricRow("Max Reps")
            Divider().overlay(ApeColor.divider.opacity(0.25))
            metricRow("Max Weight")
            Divider().overlay(ApeColor.divider.opacity(0.25))
            metricRow("Volume Weight")
        }
        .padding(ApeSpacing.md)
        .background(ApeColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: ApeRadius.card))
    }

    private func metricRow(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("–")
        }
        .font(.apeBody)
        .foregroundStyle(ApeColor.textPrimary)
        .padding(.vertical, ApeSpacing.sm)
    }

    private func finish(shouldSave: Bool) {
        saveErrorMessage = onFinish(shouldSave, rating)
    }

    private let ratingEmojis = ["😫", "😕", "😐", "🙂", "🤩"]
}

private enum ImprovementComparison: String, CaseIterable, Identifiable {
    case lifetime
    case previous

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}
