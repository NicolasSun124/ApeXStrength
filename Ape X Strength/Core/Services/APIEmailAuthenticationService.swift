import Foundation
import Security

@MainActor
final class APIEmailAuthenticationService: EmailAuthenticationService {
    private let baseURL: URL
    private let session: URLSession
    private let defaults: UserDefaults
    private let onProfileCompleted: ((AuthenticatedUser) throws -> Void)?
    private let tokenStore: AuthenticationTokenStore
    private let emailKey = "apiAuthenticatedEmail"
    private let nameKey = "apiAuthenticatedName"
    private let verifiedKey = "apiEmailVerified"

    init(
        baseURL: URL,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        onProfileCompleted: ((AuthenticatedUser) throws -> Void)? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.defaults = defaults
        self.onProfileCompleted = onProfileCompleted
        tokenStore = AuthenticationTokenStore()
    }

    var hasAuthenticatedSession: Bool {
        authenticatedUser != nil && tokenStore.read() != nil
    }

    var authenticatedUser: AuthenticatedUser? {
        guard tokenStore.read() != nil,
              defaults.bool(forKey: verifiedKey),
              let email = defaults.string(forKey: emailKey),
              let name = defaults.string(forKey: nameKey),
              !name.isEmpty else { return nil }
        return AuthenticatedUser(email: email, name: name, isEmailVerified: true)
    }

    var verifiedEmailAwaitingProfile: String? {
        guard tokenStore.read() != nil,
              defaults.bool(forKey: verifiedKey),
              defaults.string(forKey: nameKey)?.isEmpty != false else { return nil }
        return defaults.string(forKey: emailKey)
    }

    var currentSessionToken: String? { tokenStore.read() }

    func sendVerificationCode(to email: String, password: String) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedEmail.contains("@"), normalizedEmail.contains(".") else {
            throw EmailAuthenticationError.invalidEmail
        }
        guard password.count >= 8 else {
            throw EmailAuthenticationError.weakPassword
        }

        let request = try makeRequest(
            path: "auth/send-code",
            method: "POST",
            body: CredentialsRequest(email: normalizedEmail, password: password)
        )
        _ = try await perform(request)
    }

    func verify(code: String, for email: String) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let request = try makeRequest(
            path: "auth/verify-code",
            method: "POST",
            body: VerificationRequest(email: normalizedEmail, code: code)
        )
        let data = try await perform(request)
        guard let response = try? JSONDecoder().decode(AuthenticationResponse.self, from: data) else {
            throw EmailAuthenticationError.invalidResponse
        }

        try tokenStore.save(response.token)
        defaults.set(response.user.email, forKey: emailKey)
        defaults.set(response.user.emailVerified, forKey: verifiedKey)
        defaults.set(response.user.name ?? "", forKey: nameKey)
    }

    func completeProfile(name: String) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw EmailAuthenticationError.invalidName }
        guard let token = tokenStore.read(),
              let email = defaults.string(forKey: emailKey) else {
            throw EmailAuthenticationError.invalidResponse
        }

        var request = try makeRequest(path: "profile", method: "PATCH", body: ProfileRequest(name: trimmedName))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data = try await perform(request)
        guard let response = try? JSONDecoder().decode(ProfileResponse.self, from: data) else {
            throw EmailAuthenticationError.invalidResponse
        }

        let user = AuthenticatedUser(
            email: response.user.email.isEmpty ? email : response.user.email,
            name: response.user.name ?? trimmedName,
            isEmailVerified: response.user.emailVerified
        )
        try onProfileCompleted?(user)
        defaults.set(user.email, forKey: emailKey)
        defaults.set(user.name, forKey: nameKey)
        defaults.set(user.isEmailVerified, forKey: verifiedKey)
    }

    private func makeRequest<Body: Encodable>(path: String, method: String, body: Body) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmailAuthenticationError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let serverError = try? JSONDecoder().decode(ServerErrorResponse.self, from: data)
            throw EmailAuthenticationError.server(serverError?.error ?? "Authentication failed. Please try again.")
        }
        return data
    }
}

private struct CredentialsRequest: Encodable {
    let email: String
    let password: String
}

private struct VerificationRequest: Encodable {
    let email: String
    let code: String
}

private struct ProfileRequest: Encodable {
    let name: String
}

private struct AuthenticationResponse: Decodable {
    let token: String
    let user: APIUser
}

private struct ProfileResponse: Decodable {
    let user: APIUser
}

private struct APIUser: Decodable {
    let email: String
    let emailVerified: Bool
    let name: String?

    enum CodingKeys: String, CodingKey {
        case email, name
        case emailVerified = "email_verified"
    }
}

private struct ServerErrorResponse: Decodable {
    let error: String
}

private struct AuthenticationTokenStore {
    private let service = Bundle.main.bundleIdentifier ?? "ApeXStrength"
    private let account = "apiAuthenticationToken"

    func save(_ token: String) throws {
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw EmailAuthenticationError.invalidResponse
        }
    }

    func read() -> String? {
        var item = query
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
