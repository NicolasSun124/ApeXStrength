import XCTest
@testable import Ape_X_Strength

final class AuthenticationBusinessLogicTests: XCTestCase {
    @MainActor
    func testLoginNormalizesCredentialsAndCreatesSession() async throws {
        let fixture = try AuthenticationFixture()
        var completedUser: AuthenticatedUser?
        let service = TestEmailAuthenticationService(defaults: fixture.defaults) { completedUser = $0 }

        try await service.logIn(email: "  ATHLETE@Example.COM ", password: "password")

        XCTAssertTrue(service.hasAuthenticatedSession)
        XCTAssertEqual(service.authenticatedUser?.email, "athlete@example.com")
        XCTAssertEqual(service.authenticatedUser?.name, "Test Athlete")
        XCTAssertEqual(completedUser, service.authenticatedUser)
    }

    @MainActor
    func testRegistrationVerificationAndProfileCompletionStateMachine() async throws {
        let fixture = try AuthenticationFixture()
        let service = TestEmailAuthenticationService(defaults: fixture.defaults)

        try await service.sendVerificationCode(to: " New@Example.com ", password: "password")
        await XCTAssertThrowsAuthenticationError(.invalidCode) {
            try await service.verify(code: "000000", for: "new@example.com")
        }
        try await service.verify(code: "123456", for: "new@example.com")
        XCTAssertFalse(service.hasAuthenticatedSession)
        XCTAssertEqual(service.verifiedEmailAwaitingProfile, "new@example.com")

        await XCTAssertThrowsAuthenticationError(.invalidName) {
            try await service.completeProfile(name: "   ")
        }
        try await service.completeProfile(name: "  Jane Athlete  ")
        XCTAssertEqual(service.authenticatedUser?.name, "Jane Athlete")
        XCTAssertNil(service.verifiedEmailAwaitingProfile)
    }

    @MainActor
    func testAuthenticationValidationAndPasswordResetRules() async throws {
        let fixture = try AuthenticationFixture()
        let service = TestEmailAuthenticationService(defaults: fixture.defaults)

        await XCTAssertThrowsAuthenticationError(.invalidEmail) {
            try await service.logIn(email: "not-an-email", password: "password")
        }
        await XCTAssertThrowsAuthenticationError(.weakPassword) {
            try await service.sendVerificationCode(to: "a@b.com", password: "short")
        }
        await XCTAssertThrowsAuthenticationError(.invalidEmail) {
            try await service.requestPasswordReset(for: "invalid")
        }

        try await service.requestPasswordReset(for: " RESET@example.com ")
        await XCTAssertThrowsAuthenticationError(.weakPassword) {
            try await service.resetPassword(email: "reset@example.com", code: "123456", newPassword: "short")
        }
        await XCTAssertThrowsAuthenticationError(.invalidCode) {
            try await service.resetPassword(email: "reset@example.com", code: "bad", newPassword: "newpassword")
        }
        try await service.resetPassword(email: "reset@example.com", code: "123456", newPassword: "newpassword")
        await XCTAssertThrowsAuthenticationError(.invalidCode) {
            try await service.resetPassword(email: "reset@example.com", code: "123456", newPassword: "newpassword")
        }
    }

    @MainActor
    func testSignOutClearsAllAuthenticationStateAndPostsNotification() async throws {
        let fixture = try AuthenticationFixture()
        let service = TestEmailAuthenticationService(
            defaults: fixture.defaults,
            seededUser: AuthenticatedUser(email: "a@example.com", name: "A", isEmailVerified: true)
        )
        let expectation = expectation(forNotification: .authenticationDidSignOut, object: nil)

        await service.signOut()

        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertFalse(service.hasAuthenticatedSession)
        XCTAssertNil(service.authenticatedUser)
        XCTAssertNil(service.verifiedEmailAwaitingProfile)
    }
}

private struct AuthenticationFixture {
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        suiteName = "AuthenticationTests-\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private func XCTAssertThrowsAuthenticationError(
    _ expected: EmailAuthenticationError,
    operation: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await operation()
        XCTFail("Expected authentication error", file: file, line: line)
    } catch let actual as EmailAuthenticationError {
        XCTAssertEqual(actual.errorDescription, expected.errorDescription, file: file, line: line)
    } catch {
        XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
}
