import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    private let authenticationService: any EmailAuthenticationService
    private let exerciseRepository: any ExerciseRepository
    private let workoutRepository: any WorkoutRepository
    private let resetData: () throws -> Void
    @State private var isShowingResetConfirmation = false

    init(
        viewModel: @autoclosure @escaping () -> SettingsViewModel,
        authenticationService: any EmailAuthenticationService,
        exerciseRepository: any ExerciseRepository,
        workoutRepository: any WorkoutRepository,
        resetData: @escaping () throws -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.authenticationService = authenticationService
        self.exerciseRepository = exerciseRepository
        self.workoutRepository = workoutRepository
        self.resetData = resetData
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ApeSpacing.md) {
                    NavigationLink {
                        AccountSettingsView(authenticationService: authenticationService)
                    } label: {
                        ApeCard {
                            HStack(spacing: ApeSpacing.md) {
                                Image(systemName: "person.fill")
                                    .font(.title2)
                                    .foregroundStyle(ApeColor.primary)
                                    .frame(width: 52, height: 52)
                                    .background(ApeColor.primarySoft)
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: ApeSpacing.xxs) {
                                    Text(accountName)
                                        .font(.apeHeadline)
                                    Text(accountEmail)
                                        .font(.apeCallout)
                                        .foregroundStyle(ApeColor.textSecondary)
                                    Text(accountStatus)
                                        .font(.apeCaption)
                                        .foregroundStyle(accountStatusColor)
                                }

                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.apeCaption)
                                    .foregroundStyle(ApeColor.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("accountSettingsLink")

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

    private var accountName: String {
        authenticationService.authenticatedUser?.name ?? "Ape Athlete"
    }

    private var accountEmail: String {
        authenticationService.authenticatedUser?.email ?? "No email available"
    }

    private var accountStatus: String {
        authenticationService.authenticatedUser?.isEmailVerified == true
            ? "Verified email"
            : "Email not verified"
    }

    private var accountStatusColor: Color {
        authenticationService.authenticatedUser?.isEmailVerified == true
            ? ApeColor.success
            : ApeColor.warning
    }
}

private struct AccountSettingsView: View {
    let authenticationService: any EmailAuthenticationService
    @State private var isShowingPasswordReset = false
    @State private var isShowingSignOutConfirmation = false

    private var user: AuthenticatedUser? {
        authenticationService.authenticatedUser
    }

    var body: some View {
        ScrollView {
            VStack(spacing: ApeSpacing.md) {
                ApeCard {
                    VStack(spacing: ApeSpacing.md) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(ApeColor.primary)
                            .frame(width: 72, height: 72)
                            .background(ApeColor.primarySoft)
                            .clipShape(Circle())

                        VStack(spacing: ApeSpacing.xxs) {
                            Text(user?.name ?? "Ape Athlete")
                                .font(.apeHeadline)
                            Text(user?.email ?? "No email available")
                                .font(.apeCallout)
                                .foregroundStyle(ApeColor.textSecondary)
                            Label(
                                user?.isEmailVerified == true ? "Verified email" : "Email not verified",
                                systemImage: user?.isEmailVerified == true ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                            )
                            .font(.apeCaption)
                            .foregroundStyle(user?.isEmailVerified == true ? ApeColor.success : ApeColor.warning)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                Button {
                    isShowingPasswordReset = true
                } label: {
                    settingsActionLabel(
                        title: "Reset Password",
                        icon: "key.fill",
                        color: ApeColor.primary,
                        background: ApeColor.primarySoft
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settingsResetPasswordButton")

                Button {
                    isShowingSignOutConfirmation = true
                } label: {
                    settingsActionLabel(
                        title: "Sign Out",
                        icon: "rectangle.portrait.and.arrow.right",
                        color: ApeColor.textPrimary,
                        background: ApeColor.control
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("signOutButton")
            }
            .padding(ApeSpacing.md)
        }
        .background(ApeColor.background.ignoresSafeArea())
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ApeColor.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $isShowingPasswordReset) {
            SettingsPasswordResetView(
                email: user?.email ?? "",
                authenticationService: authenticationService
            )
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Sign out of Ape X Strength?",
            isPresented: $isShowingSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task { await authenticationService.signOut() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your training data will remain on this device.")
        }
    }

    private func settingsActionLabel(
        title: String,
        icon: String,
        color: Color,
        background: Color
    ) -> some View {
        HStack {
            Image(systemName: icon)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.apeCaption)
        }
        .font(.apeHeadline)
        .foregroundStyle(color)
        .padding(.horizontal, ApeSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control))
    }
}

private struct SettingsPasswordResetView: View {
    private enum Step {
        case confirmEmail
        case enterCode
        case complete
    }

    @Environment(\.dismiss) private var dismiss
    let email: String
    let authenticationService: any EmailAuthenticationService
    @State private var step: Step = .confirmEmail
    @State private var confirmedEmail = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var normalizedAccountEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var normalizedConfirmedEmail: String {
        confirmedEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: ApeSpacing.md) {
                switch step {
                case .confirmEmail:
                    confirmEmailContent
                case .enterCode:
                    enterCodeContent
                case .complete:
                    completeContent
                }
            }
            .padding(ApeSpacing.md)
            .background(ApeColor.background.ignoresSafeArea())
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var confirmEmailContent: some View {
        Label("Confirm your email", systemImage: "envelope.badge.fill")
            .font(.apeHeadline)
            .foregroundStyle(ApeColor.primary)

        Text("For security, enter the email address associated with this account. We'll send it a 6-digit reset code.")
            .font(.apeBody)
            .foregroundStyle(ApeColor.textSecondary)

        ApeFormField("Account email") {
            TextField("Email address", text: $confirmedEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(ApeTextFieldStyle())
                .accessibilityIdentifier("settingsPasswordResetEmailField")
        }

        errorText
        Spacer()

        Button {
            Task { await sendCode() }
        } label: {
            loadingLabel("Confirm Email and Send Code")
        }
        .buttonStyle(ApePrimaryButtonStyle())
        .disabled(isLoading || normalizedConfirmedEmail.isEmpty)
        .accessibilityIdentifier("settingsSendPasswordResetCodeButton")
    }

    @ViewBuilder
    private var enterCodeContent: some View {
        Label("Check your email", systemImage: "number.square.fill")
            .font(.apeHeadline)
            .foregroundStyle(ApeColor.primary)

        Text("Enter the 6-digit code sent to \(email), then choose a new password. The code expires in 10 minutes.")
            .font(.apeBody)
            .foregroundStyle(ApeColor.textSecondary)

        ApeFormField("Reset code") {
            TextField("6-digit code", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .textFieldStyle(ApeTextFieldStyle())
                .accessibilityIdentifier("settingsPasswordResetCodeField")
        }

        ApeFormField("New password") {
            SecureField("At least 8 characters", text: $newPassword)
                .textContentType(.newPassword)
                .textFieldStyle(ApeTextFieldStyle())
                .accessibilityIdentifier("settingsNewPasswordField")
        }

        errorText
        Spacer()

        Button {
            Task { await updatePassword() }
        } label: {
            loadingLabel("Update Password")
        }
        .buttonStyle(ApePrimaryButtonStyle())
        .disabled(isLoading || code.count != 6 || newPassword.count < 8)
        .accessibilityIdentifier("settingsUpdatePasswordButton")

        Button("Send a new code") {
            Task { await sendCode() }
        }
        .font(.apeCallout)
        .foregroundStyle(ApeColor.primary)
        .frame(maxWidth: .infinity)
        .disabled(isLoading)
    }

    @ViewBuilder
    private var completeContent: some View {
        Spacer()
        VStack(spacing: ApeSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(ApeColor.success)
            Text("Password updated")
                .font(.apeLargeTitle)
            Text("For security, you'll be signed out. Log in again with your new password.")
                .font(.apeBody)
                .foregroundStyle(ApeColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("Done") {
                Task {
                    await authenticationService.signOut()
                    dismiss()
                }
            }
                .buttonStyle(ApePrimaryButtonStyle())
                .accessibilityIdentifier("settingsPasswordResetDoneButton")
        }
        .frame(maxWidth: .infinity)
        Spacer()
    }

    @ViewBuilder
    private var errorText: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.apeCallout)
                .foregroundStyle(ApeColor.destructive)
        }
    }

    private func loadingLabel(_ title: String) -> some View {
        HStack {
            if isLoading { ProgressView() }
            Text(title)
        }
    }

    @MainActor
    private func sendCode() async {
        guard !isLoading else { return }
        guard normalizedConfirmedEmail == normalizedAccountEmail else {
            errorMessage = "Enter the email address associated with this account."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await authenticationService.requestPasswordReset(for: normalizedAccountEmail)
            code = ""
            step = .enterCode
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func updatePassword() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await authenticationService.resetPassword(
                email: normalizedAccountEmail,
                code: code,
                newPassword: newPassword
            )
            code = ""
            newPassword = ""
            step = .complete
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
