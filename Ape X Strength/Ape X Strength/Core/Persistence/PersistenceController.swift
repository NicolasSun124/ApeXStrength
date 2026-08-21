import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    private static let managedObjectModel: NSManagedObjectModel = {
        guard let url = Bundle.main.url(forResource: "Ape_X_Strength", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            preconditionFailure("Unable to load Ape_X_Strength.momd")
        }
        return model
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false, storeURL: URL? = nil) {
        container = NSPersistentContainer(
            name: "Ape_X_Strength",
            managedObjectModel: Self.managedObjectModel
        )

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else if let storeURL {
            container.persistentStoreDescriptions.first?.url = storeURL
        }

        container.persistentStoreDescriptions.forEach { description in
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
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
    func initializeUser(authenticatedUser: AuthenticatedUser? = nil) throws -> User {
        let context = container.viewContext
        let request = User.fetchRequest()
        request.fetchLimit = 1
        if let authenticatedUser {
            if let id = authenticatedUser.id {
                request.predicate = NSPredicate(
                    format: "serverID == %@ OR email =[c] %@",
                    id as CVarArg,
                    authenticatedUser.email
                )
            } else {
                request.predicate = NSPredicate(format: "email =[c] %@", authenticatedUser.email)
            }
        } else {
            request.predicate = NSPredicate(format: "email == %@", "local@apexstrength.app")
        }
        if let user = try context.fetch(request).first {
            if let authenticatedUser {
                try synchronize(authenticatedUser, with: user)
            }
            try claimLegacyTags(for: user)
            return user
        }

        let user = User(context: context)
        user.serverID = authenticatedUser?.id ?? UUID()
        user.createdAt = Date()
        user.email = authenticatedUser?.email ?? "local@apexstrength.app"
        user.name = authenticatedUser?.name
        user.emailVerified = authenticatedUser?.isEmailVerified ?? false
        user.preferredWeightUnit = "lbs"
        try context.save()
        return user
    }

    @MainActor
    private func claimLegacyTags(for user: User) throws {
        let request = Tag.fetchRequest()
        request.predicate = NSPredicate(format: "owner == nil")
        let tags = try container.viewContext.fetch(request)
        guard !tags.isEmpty else { return }
        tags.forEach { $0.owner = user }
        try container.viewContext.save()
    }

    @MainActor
    func synchronize(_ authenticatedUser: AuthenticatedUser, with user: User) throws {
        user.email = authenticatedUser.email
        user.name = authenticatedUser.name
        user.emailVerified = authenticatedUser.isEmailVerified
        if let id = authenticatedUser.id { user.serverID = id }
        else if user.serverID == nil { user.serverID = UUID() }
        if user.createdAt == nil { user.createdAt = Date() }
        if user.preferredWeightUnit == nil { user.preferredWeightUnit = "lbs" }
        if user.managedObjectContext?.hasChanges == true {
            try user.managedObjectContext?.save()
        }
    }

    @MainActor
    func initializeTemporaryUser() throws -> User {
        try initializeUser()
    }

    @MainActor
    func resetUserData(for user: User) throws {
        let context = container.viewContext
        let sessionRequest = WorkoutSession.fetchRequest()
        sessionRequest.predicate = NSPredicate(format: "user == %@", user)
        try context.fetch(sessionRequest).forEach(context.delete)

        let workoutRequest = WorkoutTemplate.fetchRequest()
        workoutRequest.predicate = NSPredicate(format: "user == %@", user)
        try context.fetch(workoutRequest).forEach(context.delete)

        let exerciseRequest = Exercise.fetchRequest()
        exerciseRequest.predicate = NSPredicate(format: "owner == %@", user)
        try context.fetch(exerciseRequest).forEach(context.delete)

        let tagRequest = Tag.fetchRequest()
        tagRequest.predicate = NSPredicate(format: "owner == %@", user)
        try context.fetch(tagRequest).forEach(context.delete)

        let tombstoneRequest = SyncTombstone.fetchRequest()
        tombstoneRequest.predicate = NSPredicate(format: "owner == %@", user)
        try context.fetch(tombstoneRequest).forEach(context.delete)

        user.hiddenExercises = nil
        user.syncCursor = 0

        if context.hasChanges {
            try context.save()
        }
    }

    @MainActor
    func deleteUser(_ user: User) throws {
        let context = container.viewContext
        context.delete(user)
        if context.hasChanges {
            try context.save()
        }
    }

    @MainActor
    static let preview: PersistenceController = {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext

        let user = User(context: context)
        user.serverID = UUID()
        user.email = "preview@apexstrength.app"
        user.name = "Preview Athlete"
        user.createdAt = Date()
        user.preferredWeightUnit = "lbs"

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
