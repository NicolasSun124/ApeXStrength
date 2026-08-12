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

        let user = User(context: context)
        user.serverID = UUID()
        user.email = "preview@apexstrength.app"
        user.createdAt = Date()
        user.preferredWeightUnit = "kg"

        let muscle = Muscle(context: context)
        muscle.serverID = UUID()
        muscle.name = "Full Body"
        muscle.colorHex = "8AC5FF"

        let workout = WorkoutTemplate(context: context)
        workout.clientUUID = UUID()
        workout.name = "Tracking Type Test"
        workout.createdAt = Date()
        workout.updatedAt = Date()
        workout.syncState = "synced"
        workout.user = user

        let configurations = ExerciseRepType.allCases.flatMap { repType in
            ExerciseDifficultyType.allCases.map { difficultyType in
                ExerciseConfiguration(repType: repType, difficultyType: difficultyType)
            }
        }

        let templateExercises = configurations.enumerated().map { position, configuration in
            let exercise = Exercise(context: context)
            exercise.clientUUID = UUID()
            exercise.name = "\(configuration.repType.title) + \(configuration.difficultyType.title)"
            exercise.createdAt = Date()
            exercise.trackingType = configuration.storageValue
            exercise.targetRestSeconds = 120
            exercise.syncState = "synced"
            exercise.owner = user
            exercise.primaryMuscle = muscle

            let templateExercise = TemplateExercise(context: context)
            templateExercise.clientUUID = UUID()
            templateExercise.position = Int32(position)
            templateExercise.syncState = "synced"
            templateExercise.exercise = exercise
            templateExercise.workoutTemplate = workout

            let sets = (1...3).map { setNumber in
                let set = TemplatePlannedSet(context: context)
                set.clientUUID = UUID()
                set.setNumber = Int32(setNumber)
                set.syncState = "synced"
                set.isWarmup = false
                set.templateExercise = templateExercise

                switch configuration.repType {
                case .reps:
                    set.plannedReps = Int32(8 + setNumber * 2)
                case .time:
                    set.plannedTimeSeconds = Double(20 + setNumber * 10)
                case .distance:
                    set.plannedDistance = NSDecimalNumber(value: setNumber * 100)
                }

                if configuration.difficultyType != .bodyweight {
                    set.plannedWeight = NSDecimalNumber(value: 10 + setNumber * 5)
                }

                return set
            }
            templateExercise.plannedSets = NSOrderedSet(array: sets)
            return templateExercise
        }
        workout.templateExercises = NSOrderedSet(array: templateExercises)

        try? context.save()
        return persistence
    }()
}
