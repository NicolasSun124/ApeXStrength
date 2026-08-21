//
//  Ape_X_StrengthApp.swift
//  Ape X Strength
//
//  Created by Nicolas Sun on 2026-08-10.
//

import SwiftUI

@main
struct Ape_X_StrengthApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var notificationDelegate
    @StateObject private var sessionRecoveryCoordinator = SessionRecoveryCoordinator()
    private let dependencies: AppDependencies
    private let isUITesting: Bool

    init() {
        isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        dependencies = isUITesting
            ? AppDependencies.uiTesting
            : AppDependencies.live
    }

    var body: some Scene {
        WindowGroup {
            AuthenticationGateView(
                authenticationService: dependencies.authentication,
                skipAuthentication: isUITesting
            )
                .environment(\.appDependencies, dependencies)
                .environment(\.managedObjectContext, dependencies.persistence.container.viewContext)
                .environmentObject(sessionRecoveryCoordinator)
                .tint(ApeColor.primary)
        }
    }
}
