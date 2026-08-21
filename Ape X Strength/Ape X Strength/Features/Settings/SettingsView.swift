import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    private let authenticationService: any EmailAuthenticationService
    private let exerciseRepository: any ExerciseRepository
    private let workoutRepository: any WorkoutRepository
    private let hasPendingSyncChanges: () throws -> Bool
    private let syncData: () async throws -> Void
    private let resetData: () async throws -> Void
    private let deleteAccount: () async throws -> Void
    @State private var syncStatus: SyncStatus = .ready
    @State private var isShowingSyncConfirmation = false
    @State private var isShowingSyncError = false
    @State private var isShowingResetConfirmation = false
    @State private var isShowingDeleteAccountConfirmation = false
    @State private var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @Environment(\.scenePhase) private var scenePhase

    init(
        viewModel: @autoclosure @escaping () -> SettingsViewModel,
        authenticationService: any EmailAuthenticationService,
        exerciseRepository: any ExerciseRepository,
        workoutRepository: any WorkoutRepository,
        hasPendingSyncChanges: @escaping () throws -> Bool,
        syncData: @escaping () async throws -> Void,
        resetData: @escaping () async throws -> Void,
        deleteAccount: @escaping () async throws -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.authenticationService = authenticationService
        self.exerciseRepository = exerciseRepository
        self.workoutRepository = workoutRepository
        self.hasPendingSyncChanges = hasPendingSyncChanges
        self.syncData = syncData
        self.resetData = resetData
        self.deleteAccount = deleteAccount
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ApeSpacing.md) {
                    NavigationLink {
                        AccountSettingsView(
                            authenticationService: authenticationService,
                            syncStatus: $syncStatus,
                            refreshSyncStatus: refreshSyncStatus,
                            requestSync: { isShowingSyncConfirmation = true }
                        )
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
                        VStack(alignment: .leading, spacing: ApeSpacing.sm) {
                            Toggle(isOn: $viewModel.settings.restTimerNotificationsEnabled) {
                                VStack(alignment: .leading, spacing: ApeSpacing.xxs) {
                                    Text("Rest timer alerts").font(.apeHeadline)
                                    Text("Notify me when rest is over")
                                        .font(.apeCallout).foregroundStyle(ApeColor.textSecondary)
                                }
                            }
                            .tint(ApeColor.primary)

                            if notificationAuthorizationStatus == .denied {
                                VStack(alignment: .leading, spacing: ApeSpacing.xs) {
                                    Label("Notifications are turned off for Ape X Strength.", systemImage: "bell.slash.fill")
                                        .font(.apeCallout)
                                        .foregroundStyle(ApeColor.textSecondary)
                                    Button("Open Notification Settings") { openNotificationSettings() }
                                        .font(.apeHeadline)
                                        .foregroundStyle(ApeColor.primary)
                                }
                                .accessibilityIdentifier("notificationDeniedGuidance")
                            }
                        }
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

                    HStack(spacing: ApeSpacing.sm) {
                        destructiveButton(title: "Reset Data", icon: "trash.fill") {
                            isShowingResetConfirmation = true
                        }
                        .accessibilityHint("Permanently deletes your training data")

                        destructiveButton(title: "Delete Account", icon: "person.crop.circle.badge.minus") {
                            isShowingDeleteAccountConfirmation = true
                        }
                        .accessibilityIdentifier("deleteAccountButton")
                        .accessibilityHint("Permanently deletes your account and training data")
                    }

                }
                .padding(ApeSpacing.md)
            }
            .background(ApeColor.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .toolbarBackground(ApeColor.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert("Sync your data?", isPresented: $isShowingSyncConfirmation) {
                Button("No", role: .cancel) { }
                Button("Yes") { synchronizeData() }
            } message: {
                Text("Your latest data will be uploaded and changes from your account will be downloaded.")
            }
            .alert("Sync Failed", isPresented: $isShowingSyncError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(syncStatus.message)
            }
            .sheet(isPresented: $isShowingResetConfirmation) {
                ResetDataConfirmationView {
                    try await resetData()
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isShowingDeleteAccountConfirmation) {
                DeleteAccountConfirmationView(deleteAccount: deleteAccount)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .task { await refreshNotificationAuthorization() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await refreshNotificationAuthorization() }
            }
        }
    }

    private func destructiveButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: ApeSpacing.xs) {
                Image(systemName: icon)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.apeHeadline)
            .foregroundStyle(ApeColor.destructive)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(ApeColor.destructive.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: ApeRadius.control)
                    .stroke(ApeColor.destructive, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func refreshNotificationAuthorization() async {
        notificationAuthorizationStatus = await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
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

    private func synchronizeData() {
        syncStatus = .syncing
        Task {
            do {
                try await syncData()
                syncStatus = .synced
            } catch {
                syncStatus = .failed(error.localizedDescription)
                isShowingSyncError = true
            }
        }
    }

    private func refreshSyncStatus() {
        guard syncStatus != .syncing else { return }
        do {
            syncStatus = try hasPendingSyncChanges() ? .ready : .synced
        } catch {
            syncStatus = .failed(error.localizedDescription)
        }
    }
}

private enum SyncStatus: Equatable {
    case ready
    case syncing
    case synced
    case failed(String)

    var message: String {
        switch self {
        case .ready: return "Ready to sync"
        case .syncing: return "Syncing your data…"
        case .synced: return "Your data is up to date"
        case let .failed(message): return message
        }
    }

    var icon: String {
        switch self {
        case .ready: return "xmark.circle.fill"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .synced: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .syncing: return ApeColor.primary
        case .synced: return ApeColor.success
        case .ready, .failed: return ApeColor.destructive
        }
    }
}

private struct SyncStatusCard: View {
    let status: SyncStatus

    var body: some View {
        ApeCard {
            HStack(spacing: ApeSpacing.md) {
                Group {
                    if status == .syncing {
                        ProgressView()
                            .tint(ApeColor.primary)
                    } else {
                        Image(systemName: status.icon)
                            .foregroundStyle(status.color)
                    }
                }
                .frame(width: 36, height: 36)
                .background(status.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control))

                VStack(alignment: .leading, spacing: ApeSpacing.xxs) {
                    Text("Sync Status").font(.apeHeadline)
                    Text(status.message)
                        .font(.apeCallout)
                        .foregroundStyle(status.color)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.apeCaption)
                    .foregroundStyle(ApeColor.textSecondary)
            }
        }
    }
}

private struct AccountSettingsView: View {
    let authenticationService: any EmailAuthenticationService
    @Binding var syncStatus: SyncStatus
    let refreshSyncStatus: () -> Void
    let requestSync: () -> Void
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

                Button(action: requestSync) {
                    SyncStatusCard(status: syncStatus)
                }
                .buttonStyle(.plain)
                .disabled(syncStatus == .syncing)
                .accessibilityIdentifier("accountSyncStatusButton")
                .accessibilityHint("Prompts you to sync your data")

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
        .onAppear(perform: refreshSyncStatus)
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
    @State private var isResetting = false
    let resetData: () async throws -> Void

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

                Button {
                    Task { await permanentlyResetData() }
                } label: {
                    if isResetting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Permanently Reset Data")
                    }
                }
                .font(.apeHeadline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(isConfirmed && !isResetting ? ApeColor.destructive : ApeColor.control)
                .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control))
                .disabled(!isConfirmed || isResetting)
            }
            .padding(ApeSpacing.md)
            .background(ApeColor.background.ignoresSafeArea())
            .navigationTitle("Reset Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isResetting)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    @MainActor
    private func permanentlyResetData() async {
        guard !isResetting else { return }
        isResetting = true
        errorMessage = nil
        do {
            try await resetData()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "The data could not be reset. Please try again."
            isResetting = false
        }
    }
}

private struct DeleteAccountConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmationText = ""
    @State private var errorMessage: String?
    @State private var isDeleting = false
    let deleteAccount: () async throws -> Void

    private var isConfirmed: Bool {
        confirmationText == "DELETE ACCOUNT"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: ApeSpacing.md) {
                Label("This cannot be undone", systemImage: "exclamationmark.triangle.fill")
                    .font(.apeHeadline)
                    .foregroundStyle(ApeColor.destructive)

                Text("Your account and all associated training data will be permanently deleted.")
                    .font(.apeBody)
                    .foregroundStyle(ApeColor.textSecondary)

                ApeFormField("Type DELETE ACCOUNT to confirm") {
                    TextField("DELETE ACCOUNT", text: $confirmationText)
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

                Button {
                    Task { await permanentlyDeleteAccount() }
                } label: {
                    if isDeleting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Permanently Delete Account")
                    }
                }
                .font(.apeHeadline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(isConfirmed && !isDeleting ? ApeColor.destructive : ApeColor.control)
                .clipShape(RoundedRectangle(cornerRadius: ApeRadius.control))
                .disabled(!isConfirmed || isDeleting)
                .accessibilityIdentifier("confirmDeleteAccountButton")
            }
            .padding(ApeSpacing.md)
            .background(ApeColor.background.ignoresSafeArea())
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isDeleting)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    @MainActor
    private func permanentlyDeleteAccount() async {
        guard !isDeleting else { return }
        isDeleting = true
        errorMessage = nil
        do {
            try await deleteAccount()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isDeleting = false
        }
    }
}
