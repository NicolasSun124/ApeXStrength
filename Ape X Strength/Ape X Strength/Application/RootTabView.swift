import SwiftUI

enum AppTab: Hashable {
    case workouts
    case exercises
    case settings
}

struct RootTabView: View {
    @Environment(\.appDependencies) private var dependencies
    @State private var selection: AppTab = .workouts

    var body: some View {
        TabView(selection: $selection) {
            WorkoutsView(
                viewModel: WorkoutsViewModel(repository: dependencies.workouts),
                repository: dependencies.workouts
            )
                .tabItem { Label("Workouts", systemImage: "dumbbell.fill") }
                .tag(AppTab.workouts)

            ExercisesView(
                viewModel: ExercisesViewModel(repository: dependencies.exercises),
                repository: dependencies.exercises
            )
                .tabItem { Label("Exercises", systemImage: "figure.strengthtraining.traditional") }
                .tag(AppTab.exercises)

            SettingsView(
                viewModel: SettingsViewModel(service: dependencies.settings),
                authenticationService: dependencies.authentication,
                exerciseRepository: dependencies.exercises,
                workoutRepository: dependencies.workouts,
                hasPendingSyncChanges: {
                    try dependencies.sync.hasPendingChanges()
                },
                syncData: {
                    try await dependencies.sync.syncIfNeeded()
                },
                resetData: {
                    guard let authenticatedUser = dependencies.authentication.authenticatedUser else { return }
                    let user = try dependencies.persistence.initializeUser(authenticatedUser: authenticatedUser)
                    try dependencies.persistence.resetUserData(for: user)
                }
            )
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .background(ApeColor.background)
        .toolbarBackground(ApeColor.navigation, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .preferredColorScheme(.dark)
    }
}

struct RootTabView_Previews: PreviewProvider {
    static var previews: some View {
        RootTabView()
            .environment(\.appDependencies, AppDependencies.preview)
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
