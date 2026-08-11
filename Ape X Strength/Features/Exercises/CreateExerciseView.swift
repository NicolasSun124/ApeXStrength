import SwiftUI

struct CreateExerciseView: View {
    @StateObject private var viewModel: CreateExerciseViewModel
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void

    init(viewModel: @autoclosure @escaping () -> CreateExerciseViewModel, onSaved: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ApeSpacing.lg) {
                    ApeFormField("Exercise name", message: "Required") {
                        TextField("e.g. Barbell Bench Press", text: $viewModel.name)
                            .textFieldStyle(ApeTextFieldStyle())
                            .textInputAutocapitalization(.words)
                    }

                    ApeFormField("Rep type") {
                        picker(selection: $viewModel.repType) {
                            ForEach(ExerciseRepType.allCases) { type in Text(type.title).tag(type) }
                        }
                    }

                    ApeFormField("Difficulty type") {
                        picker(selection: $viewModel.difficultyType) {
                            ForEach(ExerciseDifficultyType.allCases) { type in Text(type.title).tag(type) }
                        }
                    }

                    ApeFormField(
                        "Default rest time",
                        message: (0...59).contains(viewModel.restSeconds)
                            ? "Stored as \(viewModel.targetRestSeconds) seconds"
                            : "Seconds must be between 0 and 59"
                    ) {
                        HStack(spacing: ApeSpacing.sm) {
                            VStack(alignment: .leading, spacing: ApeSpacing.xs) {
                                Text("Minutes")
                                    .font(.apeCaption)
                                    .foregroundStyle(ApeColor.textSecondary)
                                TextField("0", value: $viewModel.restMinutes, format: .number)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(ApeTextFieldStyle())
                                    .accessibilityLabel("Rest minutes")
                            }

                            VStack(alignment: .leading, spacing: ApeSpacing.xs) {
                                Text("Seconds")
                                    .font(.apeCaption)
                                    .foregroundStyle(ApeColor.textSecondary)
                                TextField("0", value: $viewModel.restSeconds, format: .number)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(ApeTextFieldStyle())
                                    .accessibilityLabel("Rest seconds")
                            }
                        }
                    }

                    ApeFormField("Primary muscle", message: "Required") {
                        NavigationLink {
                            MuscleSelectionView(
                                title: "Primary Muscle",
                                muscles: viewModel.muscles,
                                selection: Binding(
                                    get: { viewModel.primaryMuscleID.map { [$0] } ?? [] },
                                    set: { viewModel.primaryMuscleID = $0.first }
                                ),
                                allowsMultipleSelection: false
                            )
                        } label: {
                            selectionRow(
                                text: viewModel.muscles.first { $0.id == viewModel.primaryMuscleID }?.name
                                    ?? "Select a muscle",
                                colorHex: viewModel.muscles.first { $0.id == viewModel.primaryMuscleID }?.colorHex
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    ApeFormField("Secondary muscles", message: "Optional — select all that apply") {
                        NavigationLink {
                            MuscleSelectionView(
                                title: "Secondary Muscles",
                                muscles: viewModel.muscles.filter { $0.id != viewModel.primaryMuscleID },
                                selection: $viewModel.secondaryMuscleIDs,
                                allowsMultipleSelection: true
                            )
                        } label: {
                            selectionRow(text: secondaryMuscleSummary, colorHex: nil)
                        }
                        .buttonStyle(.plain)
                    }

                    if let error = viewModel.errorMessage {
                        Text(error).font(.apeCallout).foregroundStyle(ApeColor.destructive)
                    }

                    Button(viewModel.isSaving ? "Saving…" : "Save Exercise") {
                        if viewModel.save() {
                            onSaved()
                            dismiss()
                        }
                    }
                    .buttonStyle(ApePrimaryButtonStyle())
                    .disabled(!viewModel.isValid || viewModel.isSaving)
                    .opacity(viewModel.isValid ? 1 : 0.5)
                }
                .padding(ApeSpacing.md)
            }
            .background(ApeColor.background.ignoresSafeArea())
            .navigationTitle("Create Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .task { viewModel.load() }
    }

    private func picker<Selection: Hashable, Content: View>(
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Picker("", selection: selection, content: content)
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(ApeColor.textPrimary)
            .padding(.horizontal, ApeSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background(ApeColor.control)
            .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control))
    }

    private var secondaryMuscleSummary: String {
        let selected = viewModel.muscles
            .filter { viewModel.secondaryMuscleIDs.contains($0.id) }
            .map(\.name)
        return selected.isEmpty ? "Select muscles" : selected.joined(separator: ", ")
    }

    private func selectionRow(text: String, colorHex: String?) -> some View {
        HStack(spacing: ApeSpacing.sm) {
            if let colorHex {
                Circle()
                    .fill(Color(hex: colorHex))
                    .frame(width: 14, height: 14)
            }
            Text(text)
                .font(.apeBody)
                .foregroundStyle(ApeColor.textPrimary)
                .lineLimit(2)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.apeCaption)
                .foregroundStyle(ApeColor.textSecondary)
        }
        .padding(.horizontal, ApeSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(ApeColor.control)
        .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control))
    }
}
