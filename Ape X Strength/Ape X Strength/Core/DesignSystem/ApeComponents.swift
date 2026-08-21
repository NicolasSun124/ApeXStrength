import SwiftUI
import UIKit

private struct KeyboardDoneButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                    .accessibilityIdentifier("keyboardDoneButton")
                }
            }
    }
}

extension View {
    /// Adds an explicit way to dismiss the keyboard for every kind of text input,
    /// including number and decimal pads that do not provide a return key.
    func keyboardDoneButton() -> some View {
        modifier(KeyboardDoneButton())
    }
}

struct ApePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.apeHeadline)
            .foregroundStyle(ApeColor.background)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, ApeSpacing.md)
            .background(configuration.isPressed ? ApeColor.primaryPressed : ApeColor.primary)
            .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ApeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.apeHeadline)
            .foregroundStyle(ApeColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, ApeSpacing.md)
            .background(ApeColor.control.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ApeRadius.control, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
    }
}

struct ApeCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(ApeSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ApeColor.elevated)
            .clipShape(RoundedRectangle(cornerRadius: ApeRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ApeRadius.card, style: .continuous)
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
    }
}

struct ApeTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.apeBody)
            .padding(.horizontal, ApeSpacing.md)
            .frame(minHeight: 50)
            .foregroundStyle(ApeColor.textPrimary)
            .background(ApeColor.control)
            .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ApeRadius.control, style: .continuous)
                    .stroke(ApeColor.divider, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

struct ApeFormField<Content: View>: View {
    let title: String
    let message: String?
    private let content: Content

    init(_ title: String, message: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.message = message
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ApeSpacing.xs) {
            Text(title).font(.apeCallout).foregroundStyle(ApeColor.textPrimary)
            content
            if let message {
                Text(message).font(.apeCaption).foregroundStyle(ApeColor.textSecondary)
            }
        }
    }
}

struct ApeTag: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.apeCaption)
            .foregroundStyle(ApeColor.textPrimary)
            .padding(.horizontal, ApeSpacing.sm)
            .padding(.vertical, 6)
            .background(ApeColor.control)
            .clipShape(Capsule())
    }
}
