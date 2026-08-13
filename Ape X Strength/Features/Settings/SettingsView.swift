import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    private let exerciseRepository: any ExerciseRepository
    private let workoutRepository: any WorkoutRepository

    init(
        viewModel: @autoclosure @escaping () -> SettingsViewModel,
        exerciseRepository: any ExerciseRepository,
        workoutRepository: any WorkoutRepository
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.exerciseRepository = exerciseRepository
        self.workoutRepository = workoutRepository
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ApeSpacing.md) {
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

                    ApeCard {
                        VStack(alignment: .leading, spacing: ApeSpacing.xs) {
                            Text("Account").font(.apeHeadline)
                            Text("Sign in and account management will live here.")
                                .font(.apeBody).foregroundStyle(ApeColor.textSecondary)
                        }
                    }
                }
                .padding(ApeSpacing.md)
            }
            .background(ApeColor.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .toolbarBackground(ApeColor.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
