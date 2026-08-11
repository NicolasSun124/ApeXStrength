import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Ape_X_Strength")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                assertionFailure("Core Data failed to load: \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.undoManager = nil
    }

    @MainActor
    static let preview: PersistenceController = {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext

        let workout = WorkoutTemplate(context: context)
        workout.clientUUID = UUID()
        workout.name = "Push Strength"
        workout.createdAt = Date()
        workout.updatedAt = Date()
        workout.syncState = "synced"

        let exercise = Exercise(context: context)
        exercise.clientUUID = UUID()
        exercise.name = "Barbell Bench Press"
        exercise.createdAt = Date()
        exercise.trackingType = "reps_weight"
        exercise.targetRestSeconds = 120
        exercise.syncState = "synced"

        try? context.save()
        return persistence
    }()
}
