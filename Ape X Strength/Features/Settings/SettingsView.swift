import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel

    init(viewModel: @autoclosure @escaping () -> SettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
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
                                    Text("Pounds").tag("lb")
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
