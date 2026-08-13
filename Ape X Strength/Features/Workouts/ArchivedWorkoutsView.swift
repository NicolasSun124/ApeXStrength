import SwiftUI

struct ArchivedWorkoutsView: View {
    let repository: any WorkoutRepository
    @State private var workouts: [WorkoutListItem] = []
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                ApeErrorState(message: errorMessage, retry: load)
            } else if workouts.isEmpty {
                ApeEmptyState(
                    icon: "archivebox",
                    title: "No archived workouts",
                    message: "Archived workouts will appear here."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: ApeSpacing.sm) {
                        ForEach(workouts) { workout in
                            ApeCard {
                                HStack(spacing: ApeSpacing.md) {
                                    Image(systemName: "dumbbell.fill")
                                        .foregroundStyle(ApeColor.primary)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: ApeSpacing.xxs) {
                                        Text(workout.name)
                                            .font(.apeHeadline)
                                            .foregroundStyle(ApeColor.textPrimary)
                                        Text("\(workout.exerciseCount) exercises")
                                            .font(.apeCallout)
                                            .foregroundStyle(ApeColor.textSecondary)
                                    }
                                    Spacer()
                                    Button("Restore") { restore(workout.id) }
                                        .buttonStyle(.bordered)
                                        .tint(ApeColor.primary)
                                }
                            }
                        }
                    }
                    .padding(ApeSpacing.md)
                }
                .refreshable { load() }
            }
        }
        .background(ApeColor.background.ignoresSafeArea())
        .navigationTitle("Archived Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private func load() {
        do {
            workouts = try repository.fetchArchivedWorkouts()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore(_ id: WorkoutListItem.ID) {
        do {
            try repository.restoreWorkout(id: id)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
