import SwiftUI

struct MuscleSelectionView: View {
    let title: String
    let muscles: [MuscleItem]
    @Binding var selection: Set<MuscleItem.ID>
    let allowsMultipleSelection: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(spacing: ApeSpacing.xs) {
                ForEach(muscles) { muscle in
                    Button {
                        select(muscle.id)
                    } label: {
                        HStack(spacing: ApeSpacing.md) {
                            Circle()
                                .fill(Color(hex: muscle.colorHex))
                                .frame(width: 20, height: 20)
                                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))

                            Text(muscle.name)
                                .font(.apeBody)
                                .foregroundStyle(ApeColor.textPrimary)

                            Spacer()

                            Image(systemName: selection.contains(muscle.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selection.contains(muscle.id) ? ApeColor.primary : ApeColor.textSecondary)
                        }
                        .padding(ApeSpacing.md)
                        .background(ApeColor.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(ApeSpacing.md)
        }
        .background(ApeColor.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if allowsMultipleSelection {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func select(_ id: MuscleItem.ID) {
        if allowsMultipleSelection {
            if selection.contains(id) { selection.remove(id) }
            else { selection.insert(id) }
        } else {
            selection = [id]
            dismiss()
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red, green, blue, alpha: UInt64
        switch cleaned.count {
        case 8:
            red = value >> 24
            green = value >> 16 & 0xFF
            blue = value >> 8 & 0xFF
            alpha = value & 0xFF
        default:
            red = value >> 16
            green = value >> 8 & 0xFF
            blue = value & 0xFF
            alpha = 0xFF
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}
