import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: ApeSpacing.md) {
                VStack(spacing: ApeSpacing.sm) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(ApeColor.primary)
                        .frame(width: 88, height: 88)
                        .background(ApeColor.primarySoft)
                        .clipShape(RoundedRectangle(cornerRadius: ApeRadius.card))

                    Text("Ape X Strength")
                        .font(.apeTitle)
                    Text("Train with purpose. Track every rep.")
                        .font(.apeBody)
                        .foregroundStyle(ApeColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, ApeSpacing.lg)

                ApeCard {
                    VStack(spacing: ApeSpacing.md) {
                        informationRow(label: "Version", value: version)
                        Divider().overlay(ApeColor.divider)
                        informationRow(label: "Build", value: build)
                    }
                }

                Text("Ape X Strength helps you plan workouts, track training sessions, and measure your progress over time.")
                    .font(.apeBody)
                    .foregroundStyle(ApeColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, ApeSpacing.md)
            }
            .padding(ApeSpacing.md)
        }
        .background(ApeColor.background.ignoresSafeArea())
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ApeColor.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func informationRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.apeBody)
            Spacer()
            Text(value)
                .font(.apeBody)
                .foregroundStyle(ApeColor.textSecondary)
        }
    }
}
