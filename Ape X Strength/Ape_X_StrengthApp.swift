//
//  Ape_X_StrengthApp.swift
//  Ape X Strength
//
//  Created by Nicolas Sun on 2026-08-10.
//

import SwiftUI

@main
struct Ape_X_StrengthApp: App {
    private let dependencies = AppDependencies.live

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.appDependencies, dependencies)
                .environment(\.managedObjectContext, dependencies.persistence.container.viewContext)
                .tint(ApeColor.primary)
        }
    }
}
