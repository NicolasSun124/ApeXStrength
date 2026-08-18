import SwiftUI

enum ViewLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

struct ApeLoadingView: View {
    var title = "Loading"

    var body: some View {
        VStack(spacing: ApeSpacing.md) {
            ProgressView().controlSize(.large).tint(ApeColor.primary)
            Text(title).font(.apeBody).foregroundStyle(ApeColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct ApeEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: ApeSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(ApeColor.primary)
                .frame(width: 72, height: 72)
                .background(ApeColor.primarySoft)
                .clipShape(Circle())
            Text(title).font(.apeTitle).foregroundStyle(ApeColor.textPrimary).multilineTextAlignment(.center)
            Text(message)
                .font(.apeBody)
                .foregroundStyle(ApeColor.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(ApePrimaryButtonStyle())
                    .frame(maxWidth: 280)
            }
        }
        .padding(ApeSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ApeErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ApeEmptyState(
            icon: "exclamationmark.triangle.fill",
            title: "Something went wrong",
            message: message,
            actionTitle: "Try Again",
            action: retry
        )
    }
}
