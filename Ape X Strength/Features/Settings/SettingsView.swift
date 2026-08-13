import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    private let exerciseRepository: any ExerciseRepository
    private let workoutRepository: any WorkoutRepository
    private let resetData: () throws -> Void
    @State private var isShowingResetConfirmation = false

    init(
        viewModel: @autoclosure @escaping () -> SettingsViewModel,
        exerciseRepository: any ExerciseRepository,
        workoutRepository: any WorkoutRepository,
        resetData: @escaping () throws -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.exerciseRepository = exerciseRepository
        self.workoutRepository = workoutRepository
        self.resetData = resetData
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ApeSpacing.md) {
                    ApeCard {
                        VStack(alignment: .leading, spacing: ApeSpacing.md) {
                            Text("Account").font(.apeHeadline)

                            HStack(spacing: ApeSpacing.md) {
                                Image(systemName: "person.fill")
                                    .font(.title2)
                                    .foregroundStyle(ApeColor.primary)
                                    .frame(width: 52, height: 52)
                                    .background(ApeColor.primarySoft)
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: ApeSpacing.xxs) {
                                    Text("Ape Athlete")
                                        .font(.apeHeadline)
                                    Text("local@apexstrength.app")
                                        .font(.apeCallout)
                                        .foregroundStyle(ApeColor.textSecondary)
                                    Text("Local profile")
                                        .font(.apeCaption)
                                        .foregroundStyle(ApeColor.primary)
                                }

                                Spacer()
                            }

                            Text("Profile editing and account sign-in are coming soon.")
                                .font(.apeCallout)
                                .foregroundStyle(ApeColor.textSecondary)
                        }
                    }

                    NavigationLink {
                        AboutView()
                    } label: {
                        ApeCard {
                            HStack(spacing: ApeSpacing.md) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(ApeColor.primary)
                                    .frame(width: 36, height: 36)
                                    .background(ApeColor.primarySoft)
                                    .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control))
                                VStack(alignment: .leading, spacing: ApeSpacing.xxs) {
                                    Text("About").font(.apeHeadline)
                                    Text("App information and version")
                                        .font(.apeCallout)
                                        .foregroundStyle(ApeColor.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.apeCaption)
                                    .foregroundStyle(ApeColor.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    ApeCard {
                        VStack(alignment: .leading, spacing: ApeSpacing.md) {
                            Text("Training").font(.apeHeadline)
                            ApeFormField("Weight unit") {
                                Picker("Weight unit", selection: $viewModel.settings.weightUnit) {
                                    Text("Kilograms").tag("kg")
                                    Text("Pounds").tag("lbs")
                                }
                                .pickerStyle(.segmented)
                            }
                            ApeFormField("Distance unit") {
                                Picker("Distance unit", selection: $viewModel.settings.distanceUnit) {
                                    Text("Kilometres").tag("km")
                                    Text("Miles").tag("mi")
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                    }

                    ApeCard {
                        Toggle(isOn: $viewModel.settings.restTimerNotificationsEnabled) {
                            VStack(alignment: .leading, spacing: ApeSpacing.xxs) {
                                Text("Rest timer alerts").font(.apeHeadline)
                                Text("Notify me when rest is over")
                                    .font(.apeCallout).foregroundStyle(ApeColor.textSecondary)
                            }
                        }
                        .tint(ApeColor.primary)
                    }

                    NavigationLink {
                        ArchivedExercisesView(repository: exerciseRepository) { }
                    } label: {
                        ApeCard {
                            HStack(spacing: ApeSpacing.md) {
                                Image(systemName: "archivebox.fill")
                                    .foregroundStyle(ApeColor.primary)
                                    .frame(width: 36, height: 36)
                                    .background(ApeColor.primarySoft)
                                    .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control))
                                VStack(alignment: .leading, spacing: ApeSpacing.xxs) {
                                    Text("Archived Exercises").font(.apeHeadline)
                                    Text("Restore exercises to your library")
                                        .font(.apeCallout).foregroundStyle(ApeColor.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.apeCaption).foregroundStyle(ApeColor.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        ArchivedWorkoutsView(repository: workoutRepository)
                    } label: {
                        ApeCard {
                            HStack(spacing: ApeSpacing.md) {
                                Image(systemName: "archivebox.fill")
                                    .foregroundStyle(ApeColor.primary)
                                    .frame(width: 36, height: 36)
                                    .background(ApeColor.primarySoft)
                                    .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control))
                                VStack(alignment: .leading, spacing: ApeSpacing.xxs) {
                                    Text("Archived Workouts").font(.apeHeadline)
                                    Text("Restore workouts to your list")
                                        .font(.apeCallout).foregroundStyle(ApeColor.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.apeCaption).foregroundStyle(ApeColor.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        isShowingResetConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Reset Data")
                        }
                        .font(.apeHeadline)
                        .foregroundStyle(ApeColor.destructive)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(ApeColor.destructive.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: ApeRadius.control)
                                .stroke(ApeColor.destructive, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Permanently deletes your training data")

                }
                .padding(ApeSpacing.md)
            }
            .background(ApeColor.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .toolbarBackground(ApeColor.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $isShowingResetConfirmation) {
                ResetDataConfirmationView {
                    try resetData()
                    isShowingResetConfirmation = false
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

private struct ResetDataConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmationText = ""
    @State private var errorMessage: String?
    let resetData: () throws -> Void

    private var isConfirmed: Bool {
        confirmationText == "RESET DATA"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: ApeSpacing.md) {
                Label("This cannot be undone", systemImage: "exclamationmark.triangle.fill")
                    .font(.apeHeadline)
                    .foregroundStyle(ApeColor.destructive)

                Text("All workouts, workout history, custom exercises, tags, and archived exercise choices will be permanently deleted.")
                    .font(.apeBody)
                    .foregroundStyle(ApeColor.textSecondary)

                ApeFormField("Type RESET DATA to confirm") {
                    TextField("RESET DATA", text: $confirmationText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textFieldStyle(ApeTextFieldStyle())
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.apeCallout)
                        .foregroundStyle(ApeColor.destructive)
                }

                Spacer()

                Button("Permanently Reset Data") {
                    do {
                        try resetData()
                    } catch {
                        errorMessage = "The data could not be reset. Please try again."
                    }
                }
                .font(.apeHeadline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(isConfirmed ? ApeColor.destructive : ApeColor.control)
                .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control))
                .disabled(!isConfirmed)
            }
            .padding(ApeSpacing.md)
            .background(ApeColor.background.ignoresSafeArea())
            .navigationTitle("Reset Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
