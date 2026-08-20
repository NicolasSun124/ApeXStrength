import SwiftUI

@MainActor
final class EmailAuthenticationViewModel: ObservableObject {
    enum Step {
        case login
        case signup
        case verification
        case passwordResetRequest
        case passwordResetConfirmation
        case profile
        case authenticated
    }

    @Published var email = ""
    @Published var password = ""
    @Published var verificationCode = ""
    @Published var name = ""
    @Published var newPassword = ""
    @Published var passwordResetSucceeded = false
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
            step = .login
        }
    }

    func logIn() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await service.logIn(email: email, password: password)
            if service.hasAuthenticatedSession {
                step = .authenticated
            } else if service.verifiedEmailAwaitingProfile != nil {
                step = .profile
            } else {
                throw EmailAuthenticationError.invalidResponse
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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

    func showPasswordReset() {
        password = ""
        verificationCode = ""
        errorMessage = nil
        passwordResetSucceeded = false
        step = .passwordResetRequest
    }

    func requestPasswordReset() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await service.requestPasswordReset(for: email)
            step = .passwordResetConfirmation
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func resetPassword() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await service.resetPassword(email: email, code: verificationCode, newPassword: newPassword)
            password = ""
            newPassword = ""
            verificationCode = ""
            passwordResetSucceeded = true
            step = .login
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func editCredentials() {
        verificationCode = ""
        errorMessage = nil
        step = .signup
    }

    func showSignup() {
        errorMessage = nil
        step = .signup
    }

    func showLogin() {
        verificationCode = ""
        name = ""
        errorMessage = nil
        step = .login
    }

    func handleSignOut() {
        email = ""
        password = ""
        verificationCode = ""
        name = ""
        errorMessage = nil
        step = .login
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
            case .login:
                loginView
            case .signup:
                signupView
            case .verification:
                verificationView
            case .passwordResetRequest:
                passwordResetRequestView
            case .passwordResetConfirmation:
                passwordResetConfirmationView
            case .profile:
                profileView
            case .authenticated:
                RootTabView()
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .authenticationDidSignOut)) { _ in
            viewModel.handleSignOut()
        }
    }

    private var loginView: some View {
        authenticationContainer {
            Text("Log in")
                .font(.apeLargeTitle)
                .foregroundStyle(ApeColor.textPrimary)

            Text("Welcome back. Enter your email and password to continue.")
                .font(.apeBody)
                .foregroundStyle(ApeColor.textSecondary)
                .multilineTextAlignment(.center)

            credentialsFields

            if viewModel.passwordResetSucceeded {
                Text("Password updated. Log in with your new password.")
                    .font(.apeCaption)
                    .foregroundStyle(ApeColor.primary)
                    .multilineTextAlignment(.center)
            }

            errorText

            Button {
                Task { await viewModel.logIn() }
            } label: {
                loadingLabel("Log in")
            }
            .buttonStyle(ApePrimaryButtonStyle())
            .disabled(viewModel.isLoading)
            .accessibilityIdentifier("loginButton")

            Button("Forgot password?") {
                viewModel.showPasswordReset()
            }
            .font(.apeCallout)
            .foregroundStyle(ApeColor.primary)
            .accessibilityIdentifier("forgotPasswordButton")

            Button("Don't have an account? Sign up") {
                viewModel.showSignup()
            }
            .font(.apeCallout)
            .foregroundStyle(ApeColor.primary)
        }
    }

    private var signupView: some View {
        authenticationContainer {
            Text("Create account")
                .font(.apeLargeTitle)
                .foregroundStyle(ApeColor.textPrimary)

            Text("Enter your email and choose a password. We'll send a code to verify your email.")
                .font(.apeBody)
                .foregroundStyle(ApeColor.textSecondary)
                .multilineTextAlignment(.center)

            credentialsFields

            errorText

            Button {
                Task { await viewModel.sendCode() }
            } label: {
                loadingLabel("Send verification code")
            }
            .buttonStyle(ApePrimaryButtonStyle())
            .disabled(viewModel.isLoading)
            .accessibilityIdentifier("sendVerificationCodeButton")

            Button("Already have an account? Log in") {
                viewModel.showLogin()
            }
            .font(.apeCallout)
            .foregroundStyle(ApeColor.primary)
        }
    }

    private var credentialsFields: some View {
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

    private var passwordResetRequestView: some View {
        authenticationContainer {
            Text("Reset password")
                .font(.apeLargeTitle)
                .foregroundStyle(ApeColor.textPrimary)

            Text("Enter your email and we'll send you a 6-digit reset code.")
                .font(.apeBody)
                .foregroundStyle(ApeColor.textSecondary)
                .multilineTextAlignment(.center)

            TextField("Email address", text: $viewModel.email)
                .textFieldStyle(ApeTextFieldStyle())
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            errorText

            Button {
                Task { await viewModel.requestPasswordReset() }
            } label: {
                loadingLabel("Send reset code")
            }
            .buttonStyle(ApePrimaryButtonStyle())
            .disabled(viewModel.isLoading)
            .accessibilityIdentifier("sendPasswordResetCodeButton")

            Button("Back to log in") { viewModel.showLogin() }
                .font(.apeCallout)
                .foregroundStyle(ApeColor.primary)
        }
    }

    private var passwordResetConfirmationView: some View {
        authenticationContainer {
            Text("Choose a new password")
                .font(.apeLargeTitle)
                .foregroundStyle(ApeColor.textPrimary)
                .multilineTextAlignment(.center)

            Text("If an account exists for \(viewModel.email), a 6-digit code was sent. It expires in 10 minutes.")
                .font(.apeBody)
                .foregroundStyle(ApeColor.textSecondary)
                .multilineTextAlignment(.center)

            TextField("Reset code", text: $viewModel.verificationCode)
                .textFieldStyle(ApeTextFieldStyle())
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)

            SecureField("New password", text: $viewModel.newPassword)
                .textFieldStyle(ApeTextFieldStyle())
                .textContentType(.newPassword)

            errorText

            Button {
                Task { await viewModel.resetPassword() }
            } label: {
                loadingLabel("Update password")
            }
            .buttonStyle(ApePrimaryButtonStyle())
            .disabled(viewModel.isLoading || viewModel.verificationCode.count != 6 || viewModel.newPassword.count < 8)
            .accessibilityIdentifier("resetPasswordButton")

            Button("Request another code") { viewModel.showPasswordReset() }
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
