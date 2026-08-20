import Foundation

struct AuthenticatedUser: Equatable {
    let id: UUID?
    let email: String
    let name: String
    let isEmailVerified: Bool

    init(id: UUID? = nil, email: String, name: String, isEmailVerified: Bool) {
        self.id = id
        self.email = email
        self.name = name
        self.isEmailVerified = isEmailVerified
    }
}

enum EmailAuthenticationError: LocalizedError {
    case invalidEmail
    case weakPassword
    case invalidCode
    case invalidName
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Enter a valid email address."
        case .weakPassword:
            return "Your password must contain at least 8 characters."
        case .invalidCode:
            return "That verification code is incorrect."
        case .invalidName:
            return "Enter your name to continue."
        case .invalidResponse:
            return "The authentication server returned an invalid response."
        case .server(let message):
            return message
        }
    }
}

@MainActor
protocol EmailAuthenticationService: AnyObject {
    var hasAuthenticatedSession: Bool { get }
    var authenticatedUser: AuthenticatedUser? { get }
    var verifiedEmailAwaitingProfile: String? { get }
    func logIn(email: String, password: String) async throws
    func sendVerificationCode(to email: String, password: String) async throws
    func verify(code: String, for email: String) async throws
    func completeProfile(name: String) async throws
    func signOut() async
}

/// Temporary local implementation used until a real authentication/email provider is connected.
/// It deliberately keeps credentials in memory and only persists whether verification succeeded.
@MainActor
final class TestEmailAuthenticationService: EmailAuthenticationService {
    private let defaults: UserDefaults
    private let onProfileCompleted: ((AuthenticatedUser) throws -> Void)?
    private let sessionKey = "temporaryEmailAuthenticationSession"
    private let emailKey = "temporaryAuthenticatedEmail"
    private let nameKey = "temporaryAuthenticatedName"
    private let emailVerifiedKey = "temporaryEmailVerified"
    private var pendingCodes: [String: String] = [:]

    init(
        defaults: UserDefaults = .standard,
        seededUser: AuthenticatedUser? = nil,
        onProfileCompleted: ((AuthenticatedUser) throws -> Void)? = nil
    ) {
        self.defaults = defaults
        self.onProfileCompleted = onProfileCompleted
        if let seededUser {
            defaults.set(seededUser.email, forKey: emailKey)
            defaults.set(seededUser.name, forKey: nameKey)
            defaults.set(seededUser.isEmailVerified, forKey: emailVerifiedKey)
            defaults.set(true, forKey: sessionKey)
        }
    }

    var hasAuthenticatedSession: Bool {
        authenticatedUser != nil
    }

    var authenticatedUser: AuthenticatedUser? {
        guard defaults.bool(forKey: sessionKey),
              let email = defaults.string(forKey: emailKey),
              let name = defaults.string(forKey: nameKey),
              !email.isEmpty, !name.isEmpty else { return nil }
        return AuthenticatedUser(email: email, name: name, isEmailVerified: true)
    }

    var verifiedEmailAwaitingProfile: String? {
        guard defaults.bool(forKey: emailVerifiedKey),
              !defaults.bool(forKey: sessionKey) else { return nil }
        return defaults.string(forKey: emailKey)
    }

    func logIn(email: String, password: String) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedEmail.contains("@"), normalizedEmail.contains(".") else {
            throw EmailAuthenticationError.invalidEmail
        }
        guard password.count >= 8 else { throw EmailAuthenticationError.weakPassword }

        let user = AuthenticatedUser(email: normalizedEmail, name: "Test Athlete", isEmailVerified: true)
        try onProfileCompleted?(user)
        defaults.set(normalizedEmail, forKey: emailKey)
        defaults.set(user.name, forKey: nameKey)
        defaults.set(true, forKey: emailVerifiedKey)
        defaults.set(true, forKey: sessionKey)
    }

    func sendVerificationCode(to email: String, password: String) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedEmail.contains("@"), normalizedEmail.contains(".") else {
            throw EmailAuthenticationError.invalidEmail
        }
        guard password.count >= 8 else {
            throw EmailAuthenticationError.weakPassword
        }

        try await Task.sleep(for: .milliseconds(500))
        let code = "123456"
        pendingCodes[normalizedEmail] = code
    }

    func verify(code: String, for email: String) async throws {
        try await Task.sleep(for: .milliseconds(350))
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard pendingCodes[normalizedEmail] == code else {
            throw EmailAuthenticationError.invalidCode
        }

        pendingCodes[normalizedEmail] = nil
        defaults.set(normalizedEmail, forKey: emailKey)
        defaults.set(true, forKey: emailVerifiedKey)
        defaults.set(false, forKey: sessionKey)
    }

    func completeProfile(name: String) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw EmailAuthenticationError.invalidName
        }
        guard verifiedEmailAwaitingProfile != nil else {
            throw EmailAuthenticationError.invalidCode
        }

        let email = verifiedEmailAwaitingProfile ?? ""
        let user = AuthenticatedUser(email: email, name: trimmedName, isEmailVerified: true)
        try onProfileCompleted?(user)
        defaults.set(trimmedName, forKey: nameKey)
        defaults.set(true, forKey: sessionKey)
    }

    func signOut() async {
        defaults.removeObject(forKey: sessionKey)
        defaults.removeObject(forKey: emailKey)
        defaults.removeObject(forKey: nameKey)
        defaults.removeObject(forKey: emailVerifiedKey)
        NotificationCenter.default.post(name: .authenticationDidSignOut, object: nil)
    }
}

extension Notification.Name {
    static let authenticationDidSignOut = Notification.Name("authenticationDidSignOut")
}
