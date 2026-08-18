import SwiftUI

@MainActor
final class EmailAuthenticationViewModel: ObservableObject {
    enum Step {
        case credentials
        case verification
        case profile
        case authenticated
    }

    @Published var email = ""
    @Published var password = ""
    @Published var verificationCode = ""
    @Published var name = ""
    @Published private(set) var step: Step
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service: any EmailAuthenticationService

    init(service: any EmailAuthenticationService, skipAuthentication: Bool = false) {
        self.service = service
        if skipAuthentication || service.hasAuthenticatedSession {
            step = .authenticated
        } else if let verifiedEmail = service.verifiedEmailAwaitingProfile {
            email = verifiedEmail
            step = .profile
        } else {
            step = .credentials
        }
    }

    func sendCode() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await service.sendVerificationCode(to: email, password: password)
            step = .verification
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func verifyCode() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await service.verify(code: verificationCode, for: email)
            step = .profile
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func completeProfile() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await service.completeProfile(name: name)
            step = .authenticated
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func editCredentials() {
        verificationCode = ""
        errorMessage = nil
        step = .credentials
    }
}

struct AuthenticationGateView: View {
    @StateObject private var viewModel: EmailAuthenticationViewModel

    init(authenticationService: any EmailAuthenticationService, skipAuthentication: Bool = false) {
        _viewModel = StateObject(
            wrappedValue: EmailAuthenticationViewModel(
                service: authenticationService,
                skipAuthentication: skipAuthentication
            )
        )
    }

    var body: some View {
        Group {
            switch viewModel.step {
            case .credentials:
                credentialsView
            case .verification:
                verificationView
            case .profile:
                profileView
            case .authenticated:
                RootTabView()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var credentialsView: some View {
        authenticationContainer {
            Text("Sign in")
                .font(.apeLargeTitle)
                .foregroundStyle(ApeColor.textPrimary)

            Text("Enter your email and password. We'll send a verification code to confirm your email.")
                .font(.apeBody)
                .foregroundStyle(ApeColor.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: ApeSpacing.md) {
                TextField("Email address", text: $viewModel.email)
                    .textFieldStyle(ApeTextFieldStyle())
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("emailField")

                SecureField("Password", text: $viewModel.password)
                    .textFieldStyle(ApeTextFieldStyle())
                    .textContentType(.password)
                    .accessibilityIdentifier("passwordField")
            }

            errorText

            Button {
                Task { await viewModel.sendCode() }
            } label: {
                loadingLabel("Send verification code")
            }
            .buttonStyle(ApePrimaryButtonStyle())
            .disabled(viewModel.isLoading)
            .accessibilityIdentifier("sendVerificationCodeButton")
        }
    }

    private var verificationView: some View {
        authenticationContainer {
            Text("Check your email")
                .font(.apeLargeTitle)
                .foregroundStyle(ApeColor.textPrimary)

            Text("Enter the 6-digit code sent to \(viewModel.email).")
                .font(.apeBody)
                .foregroundStyle(ApeColor.textSecondary)
                .multilineTextAlignment(.center)

            TextField("Verification code", text: $viewModel.verificationCode)
                .textFieldStyle(ApeTextFieldStyle())
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("verificationCodeField")

            errorText

            Button {
                Task { await viewModel.verifyCode() }
            } label: {
                loadingLabel("Verify and continue")
            }
            .buttonStyle(ApePrimaryButtonStyle())
            .disabled(viewModel.isLoading || viewModel.verificationCode.count != 6)
            .accessibilityIdentifier("verifyCodeButton")

            Button("Use a different email") {
                viewModel.editCredentials()
            }
            .font(.apeCallout)
            .foregroundStyle(ApeColor.primary)
        }
    }

    private var profileView: some View {
        authenticationContainer {
            Text("What should we call you?")
                .font(.apeLargeTitle)
                .foregroundStyle(ApeColor.textPrimary)
                .multilineTextAlignment(.center)

            Text("Your email is verified. Add your name to finish setting up your profile.")
                .font(.apeBody)
                .foregroundStyle(ApeColor.textSecondary)
                .multilineTextAlignment(.center)

            TextField("Your name", text: $viewModel.name)
                .textFieldStyle(ApeTextFieldStyle())
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("nameField")

            errorText

            Button {
                Task { await viewModel.completeProfile() }
            } label: {
                loadingLabel("Continue")
            }
            .buttonStyle(ApePrimaryButtonStyle())
            .disabled(viewModel.isLoading || viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("completeProfileButton")
        }
    }

    private func authenticationContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            ApeColor.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: ApeSpacing.lg) {
                    Image("Icon with white edge")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .accessibilityHidden(true)
                    content()
                }
                .padding(.horizontal, ApeSpacing.lg)
                .padding(.vertical, ApeSpacing.xxl)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var errorText: some View {
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(.apeCaption)
                .foregroundStyle(ApeColor.destructive)
                .multilineTextAlignment(.center)
        }
    }

    private func loadingLabel(_ title: String) -> some View {
        HStack {
            if viewModel.isLoading { ProgressView() }
            Text(title)
        }
    }
}

struct AuthenticationGateView_Previews: PreviewProvider {
    static var previews: some View {
        AuthenticationGateView(authenticationService: TestEmailAuthenticationService())
            .environment(\.appDependencies, AppDependencies.preview)
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
