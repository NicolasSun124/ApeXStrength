import SwiftUI

struct WorkoutFinishView: View {
    let workoutName: String
    let improvements: [ExerciseImprovementSummary]
    let onFinish: (_ shouldSave: Bool, _ rating: Int, _ note: String) -> String?
    @State private var rating = 3
    @State private var note = ""
    @State private var comparison: ImprovementComparison = .lifetime
    @State private var isConfirmingFinish = false
    @State private var saveErrorMessage: String?
    @FocusState private var isNoteFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ApeSpacing.lg) {
                ratingSection
                noteSection
                improvementsSection
            }
            .padding(ApeSpacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
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
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isNoteFocused = false }
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

            ForEach(improvements) { improvement in
                exerciseImprovementCard(improvement)
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: ApeSpacing.sm) {
            Text("Session Note")
                .font(.apeHeadline)
                .foregroundStyle(ApeColor.textPrimary)

            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text("How did the session feel?")
                        .font(.apeBody)
                        .foregroundStyle(ApeColor.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $note)
                    .font(.apeBody)
                    .foregroundStyle(ApeColor.textPrimary)
                    .focused($isNoteFocused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .accessibilityLabel("Session note")
            }
            .padding(ApeSpacing.sm)
            .background(ApeColor.control)
            .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control))
        }
        .padding(ApeSpacing.md)
        .background(ApeColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: ApeRadius.card))
    }

    private func exerciseImprovementCard(_ improvement: ExerciseImprovementSummary) -> some View {
        let metrics = comparison == .lifetime ? improvement.lifetime : improvement.previous
        return VStack(alignment: .leading, spacing: 0) {
            Text(improvement.exerciseName)
                .font(.apeHeadline)
                .foregroundStyle(ApeColor.textPrimary)
                .padding(.bottom, ApeSpacing.xs)

            ForEach(Array(metrics.metrics.enumerated()), id: \.element.id) { index, metric in
                metricRow(metric.title, metric: metric)
                if index < metrics.metrics.count - 1 {
                    Divider().overlay(ApeColor.divider.opacity(0.25))
                }
            }
        }
        .padding(ApeSpacing.md)
        .background(ApeColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: ApeRadius.card))
    }

    private func metricRow(_ title: String, metric: ImprovementMetric) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(metric.displayValue)
                .foregroundStyle(metricColor(metric.trend))
        }
        .font(.apeBody)
        .foregroundStyle(ApeColor.textPrimary)
        .padding(.vertical, ApeSpacing.sm)
    }

    private func metricColor(_ trend: ImprovementTrend) -> Color {
        switch trend {
        case .improved: ApeColor.success
        case .maintained, .firstEntry: ApeColor.textSecondary
        case .regressed: ApeColor.destructive
        }
    }

    private func finish(shouldSave: Bool) {
        saveErrorMessage = onFinish(shouldSave, rating, note)
    }

    private let ratingEmojis = ["😫", "😕", "😐", "🙂", "🤩"]
}

private enum ImprovementComparison: String, CaseIterable, Identifiable {
    case lifetime
    case previous

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}
