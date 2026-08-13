import SwiftUI

struct ArchivedExercisesView: View {
    let repository: any ExerciseRepository
    let onRestored: () -> Void
    @State private var exercises: [ExerciseListItem] = []
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                ApeErrorState(message: errorMessage, retry: load)
            } else if exercises.isEmpty {
                ApeEmptyState(
                    icon: "archivebox",
                    title: "No archived exercises",
                    message: "Archived exercises will appear here."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: ApeSpacing.sm) {
                        ForEach(exercises) { exercise in
                            ApeCard {
                                HStack(spacing: ApeSpacing.md) {
                                    Circle()
                                        .fill(Color(hex: exercise.primaryMuscleColorHex))
                                        .frame(width: 16, height: 16)
                                    Text(exercise.name)
                                        .font(.apeHeadline)
                                        .foregroundStyle(ApeColor.textPrimary)
                                    Spacer()
                                    Button("Restore") { restore(exercise.id) }
                                        .buttonStyle(.bordered)
                                        .tint(ApeColor.primary)
                                }
                            }
                        }
                    }
                    .padding(ApeSpacing.md)
                }
            }
        }
        .background(ApeColor.background.ignoresSafeArea())
        .navigationTitle("Archived Exercises")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private func load() {
        do {
            exercises = try repository.fetchArchivedExercises()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore(_ id: ExerciseListItem.ID) {
        do {
            try repository.restoreExercise(id: id)
            load()
            onRestored()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
