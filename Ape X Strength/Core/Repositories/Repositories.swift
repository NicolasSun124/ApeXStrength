import CoreData
import Foundation

@MainActor
protocol WorkoutRepository {
    func fetchWorkouts() throws -> [WorkoutListItem]
    func fetchWorkoutPreview(id: NSManagedObjectID) throws -> WorkoutPreview
    func fetchActiveSessionDraft() throws -> WorkoutSessionDraft?
    func archiveWorkout(id: NSManagedObjectID) throws
    func removeExercise(id: NSManagedObjectID, fromWorkout id: NSManagedObjectID) throws
    func reorderExercises(_ exerciseIDs: [NSManagedObjectID], inWorkout id: NSManagedObjectID) throws
    func setAlternateExercises(_ alternateIDs: Set<NSManagedObjectID>, forExercise id: NSManagedObjectID, inWorkout workoutID: NSManagedObjectID) throws
    func replaceExercise(_ id: NSManagedObjectID, with alternateID: NSManagedObjectID, inWorkout workoutID: NSManagedObjectID) throws
    func startSession(
        workoutID: NSManagedObjectID,
        startedAt: Date,
        exercises: [CompletedSessionExercise]
    ) throws -> NSManagedObjectID
    func updateActiveSession(id: NSManagedObjectID, exercises: [CompletedSessionExercise]) throws
    func discardSession(id: NSManagedObjectID) throws
    func saveCompletedSession(_ input: CompletedWorkoutSession) throws
    func calculateImprovements(for exercises: [CompletedSessionExercise]) throws -> [ExerciseImprovementSummary]
    func fetchAvailableExercises() throws -> [ExerciseListItem]
    func fetchTags() throws -> [TagItem]
    @discardableResult func createTag(named name: String) throws -> TagItem
    @discardableResult func createWorkout(_ input: NewWorkout) throws -> WorkoutListItem
}

@MainActor
protocol ExerciseRepository {
    func fetchExercises() throws -> [ExerciseListItem]
    func fetchExercise(id: NSManagedObjectID) throws -> ExerciseDetail
    func fetchMuscles() throws -> [MuscleItem]
    @discardableResult func createExercise(_ input: NewExercise) throws -> ExerciseListItem
}

@MainActor
final class CoreDataWorkoutRepository: WorkoutRepository {
    private let context: NSManagedObjectContext
    private let settings: any SettingsService
    private let user: User

    init(context: NSManagedObjectContext, settings: any SettingsService, user: User) {
        self.context = context
        self.settings = settings
        self.user = user
    }

    private var selectedWeightUnit: WeightUnit { WeightUnit(setting: settings.load().weightUnit) }

    func fetchWorkouts() throws -> [WorkoutListItem] {
        let request = WorkoutTemplate.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        request.predicate = NSPredicate(format: "isArchived == NO")

        return try context.fetch(request).map { workout in
            let sessions = (workout.sessions as? Set<WorkoutSession> ?? [])
                .filter { $0.endedAt != nil }
            return WorkoutListItem(
                id: workout.objectID,
                name: workout.name ?? "Untitled Workout",
                exerciseCount: workout.templateExercises?.count ?? 0,
                updatedAt: workout.updatedAt ?? .distantPast,
                tags: (workout.tags as? Set<Tag> ?? [])
                    .compactMap { tag in
                        guard let name = tag.name else { return nil }
                        return WorkoutTagSummary(name: name, color: TagColor(name: name))
                    }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
                statistics: workoutStatistics(from: Array(sessions))
            )
        }
    }

    func fetchWorkoutPreview(id: NSManagedObjectID) throws -> WorkoutPreview {
        guard let workout = try context.existingObject(with: id) as? WorkoutTemplate,
              !workout.isDeleted,
              !workout.isArchived else {
            throw WorkoutRepositoryError.workoutNotFound
        }

        let templateExercises = (workout.templateExercises?.array as? [TemplateExercise] ?? [])
            .sorted { $0.position < $1.position }

        return WorkoutPreview(
            id: workout.objectID,
            name: workout.name ?? "Untitled Workout",
            tags: (workout.tags as? Set<Tag> ?? [])
                .compactMap { tag in
                    guard let name = tag.name else { return nil }
                    return WorkoutTagSummary(name: name, color: TagColor(name: name))
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            exercises: templateExercises.compactMap { templateExercise in
                guard let exercise = templateExercise.exercise else { return nil }
                let configuration = ExerciseConfiguration(storageValue: exercise.trackingType ?? "")
                let previousSets = latestSessionSets(for: exercise)
                let plannedSets = (templateExercise.plannedSets?.array as? [TemplatePlannedSet] ?? [])
                    .sorted { $0.setNumber < $1.setNumber }

                return WorkoutPreviewExercise(
                    id: exercise.objectID,
                    name: exercise.name ?? "Untitled Exercise",
                    primaryMuscleColorHex: exercise.primaryMuscle?.colorHex ?? "8AC5FF",
                    repType: configuration.repType,
                    difficultyType: configuration.difficultyType,
                    targetRestSeconds: Int(exercise.targetRestSeconds),
                    sets: plannedSets.enumerated().map { index, plannedSet in
                        let setNumber = plannedSet.setNumber > 0 ? Int(plannedSet.setNumber) : index + 1
                        let previous = previousSets.first { Int($0.setNumber) == setNumber }
                        return WorkoutPreviewSet(
                            number: setNumber,
                            reps: previous.map { Int($0.reps) } ?? 0,
                            timeSeconds: previous?.timeSeconds ?? 0,
                            distance: previous?.distance as Decimal? ?? 0,
                            weight: selectedWeightUnit.displayed(fromPounds: previous?.weight as Decimal? ?? 0)
                        )
                    },
                    alternates: (templateExercise.alternateExercises as? Set<Exercise> ?? [])
                        .map(exerciseListItem)
                        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                )
            }
        )
    }

    func fetchActiveSessionDraft() throws -> WorkoutSessionDraft? {
        let request = WorkoutSession.fetchRequest()
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        request.predicate = NSPredicate(format: "endedAt == nil AND user == %@ AND workoutTemplate != nil", user)
        guard let session = try context.fetch(request).first,
              let workout = session.workoutTemplate else { return nil }

        let templateItems = orderedTemplateExercises(in: workout)
        let occurrences = (session.sessionExercises?.array as? [SessionExercise] ?? [])
            .sorted { $0.position < $1.position }
        var completedSets: [NSManagedObjectID: Set<Int>] = [:]

        let exercises = occurrences.compactMap { occurrence -> WorkoutPreviewExercise? in
            guard let exercise = occurrence.exercise else { return nil }
            let configuration = ExerciseConfiguration(storageValue: exercise.trackingType ?? "")
            let sets = (occurrence.sets?.array as? [SessionSet] ?? [])
                .sorted { $0.setNumber < $1.setNumber }
            completedSets[exercise.objectID] = Set(sets.filter(\.completed).map { Int($0.setNumber) })
            let templateItem = templateItems.first { $0.exercise == exercise }

            return WorkoutPreviewExercise(
                id: exercise.objectID,
                name: exercise.name ?? "Untitled Exercise",
                primaryMuscleColorHex: exercise.primaryMuscle?.colorHex ?? "8AC5FF",
                repType: configuration.repType,
                difficultyType: configuration.difficultyType,
                targetRestSeconds: Int(exercise.targetRestSeconds),
                sets: sets.map { set in
                    WorkoutPreviewSet(
                        number: Int(set.setNumber),
                        reps: Int(set.reps),
                        timeSeconds: set.timeSeconds,
                        distance: set.distance as Decimal? ?? 0,
                        weight: selectedWeightUnit.displayed(fromPounds: set.weight as Decimal? ?? 0)
                    )
                },
                alternates: (templateItem?.alternateExercises as? Set<Exercise> ?? [])
                    .map(exerciseListItem)
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            )
        }

        return WorkoutSessionDraft(
            id: session.objectID,
            workout: WorkoutPreview(
                id: workout.objectID,
                name: workout.name ?? "Untitled Workout",
                tags: [],
                exercises: exercises
            ),
            startedAt: session.startedAt ?? Date(),
            completedSetNumbersByExerciseID: completedSets
        )
    }

    func archiveWorkout(id: NSManagedObjectID) throws {
        guard let workout = try context.existingObject(with: id) as? WorkoutTemplate,
              !workout.isDeleted,
              !workout.isArchived else {
            throw WorkoutRepositoryError.workoutNotFound
        }

        workout.isArchived = true
        workout.updatedAt = Date()
        workout.syncState = "pendingUpdate"
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func removeExercise(id exerciseID: NSManagedObjectID, fromWorkout workoutID: NSManagedObjectID) throws {
        let workout = try editableWorkout(id: workoutID)
        var items = orderedTemplateExercises(in: workout)
        guard let index = items.firstIndex(where: { $0.exercise?.objectID == exerciseID }) else {
            throw WorkoutRepositoryError.exerciseNotFound
        }
        let removed = items.remove(at: index)
        context.delete(removed)
        apply(items, to: workout)
        try saveWorkoutChanges()
    }

    func reorderExercises(_ exerciseIDs: [NSManagedObjectID], inWorkout workoutID: NSManagedObjectID) throws {
        let workout = try editableWorkout(id: workoutID)
        let existing = orderedTemplateExercises(in: workout)
        let byExerciseID = Dictionary(uniqueKeysWithValues: existing.compactMap { item in
            item.exercise.map { ($0.objectID, item) }
        })
        guard exerciseIDs.count == existing.count,
              Set(exerciseIDs) == Set(byExerciseID.keys) else {
            throw WorkoutRepositoryError.exerciseNotFound
        }
        apply(exerciseIDs.compactMap { byExerciseID[$0] }, to: workout)
        try saveWorkoutChanges()
    }

    func setAlternateExercises(
        _ alternateIDs: Set<NSManagedObjectID>,
        forExercise exerciseID: NSManagedObjectID,
        inWorkout workoutID: NSManagedObjectID
    ) throws {
        let workout = try editableWorkout(id: workoutID)
        guard let item = orderedTemplateExercises(in: workout).first(where: { $0.exercise?.objectID == exerciseID }) else {
            throw WorkoutRepositoryError.exerciseNotFound
        }
        let alternates = try alternateIDs.compactMap { try context.existingObject(with: $0) as? Exercise }
        item.alternateExercises = Set(alternates) as NSSet
        item.syncState = "pendingUpdate"
        workout.updatedAt = Date()
        workout.syncState = "pendingUpdate"
        try saveWorkoutChanges()
    }

    func replaceExercise(
        _ exerciseID: NSManagedObjectID,
        with alternateID: NSManagedObjectID,
        inWorkout workoutID: NSManagedObjectID
    ) throws {
        let workout = try editableWorkout(id: workoutID)
        let items = orderedTemplateExercises(in: workout)
        guard let item = items.first(where: { $0.exercise?.objectID == exerciseID }),
              let current = item.exercise,
              let replacement = try context.existingObject(with: alternateID) as? Exercise,
              !items.contains(where: { $0 !== item && $0.exercise?.objectID == alternateID }) else {
            throw WorkoutRepositoryError.exerciseNotFound
        }
        var alternates = item.alternateExercises as? Set<Exercise> ?? []
        alternates.remove(replacement)
        alternates.insert(current)
        item.exercise = replacement
        item.alternateExercises = alternates as NSSet
        item.syncState = "pendingUpdate"
        workout.updatedAt = Date()
        workout.syncState = "pendingUpdate"
        try saveWorkoutChanges()
    }

    private func exerciseListItem(_ exercise: Exercise) -> ExerciseListItem {
        let configuration = ExerciseConfiguration(storageValue: exercise.trackingType ?? "")
        return ExerciseListItem(
            id: exercise.objectID,
            name: exercise.name ?? "Untitled Exercise",
            primaryMuscleColorHex: exercise.primaryMuscle?.colorHex ?? "8AC5FF",
            repType: configuration.repType,
            difficultyType: configuration.difficultyType,
            targetRestSeconds: Int(exercise.targetRestSeconds)
        )
    }

    private func editableWorkout(id: NSManagedObjectID) throws -> WorkoutTemplate {
        guard let workout = try context.existingObject(with: id) as? WorkoutTemplate,
              !workout.isDeleted,
              !workout.isArchived else {
            throw WorkoutRepositoryError.workoutNotFound
        }
        return workout
    }

    private func orderedTemplateExercises(in workout: WorkoutTemplate) -> [TemplateExercise] {
        (workout.templateExercises?.array as? [TemplateExercise] ?? []).sorted { $0.position < $1.position }
    }

    private func apply(_ exercises: [TemplateExercise], to workout: WorkoutTemplate) {
        for (position, exercise) in exercises.enumerated() {
            exercise.position = Int32(position)
            exercise.syncState = "pendingUpdate"
        }
        workout.templateExercises = NSOrderedSet(array: exercises)
        workout.updatedAt = Date()
        workout.syncState = "pendingUpdate"
    }

    private func saveWorkoutChanges() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func startSession(
        workoutID: NSManagedObjectID,
        startedAt: Date,
        exercises: [CompletedSessionExercise]
    ) throws -> NSManagedObjectID {
        guard let workout = try context.existingObject(with: workoutID) as? WorkoutTemplate,
              !workout.isDeleted,
              !workout.isArchived else {
            throw WorkoutRepositoryError.workoutNotFound
        }

        let session = WorkoutSession(context: context)
        session.clientUUID = UUID()
        session.startedAt = startedAt
        session.syncState = "pendingCreate"
        session.workoutTemplate = workout
        session.user = workout.user

        do {
            try replaceContents(of: session, with: exercises, completedAt: startedAt)
            try context.save()
            return session.objectID
        } catch {
            context.rollback()
            throw error
        }
    }

    func discardSession(id: NSManagedObjectID) throws {
        guard let session = try context.existingObject(with: id) as? WorkoutSession,
              !session.isDeleted else { return }
        context.delete(session)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func updateActiveSession(id: NSManagedObjectID, exercises: [CompletedSessionExercise]) throws {
        guard let session = try context.existingObject(with: id) as? WorkoutSession,
              !session.isDeleted,
              session.endedAt == nil else {
            throw WorkoutRepositoryError.sessionNotFound
        }

        do {
            try replaceContents(of: session, with: exercises, completedAt: Date())
            session.durationSeconds = Int64(max(0, Date().timeIntervalSince(session.startedAt ?? Date())))
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func saveCompletedSession(_ input: CompletedWorkoutSession) throws {
        guard let workout = try context.existingObject(with: input.workoutID) as? WorkoutTemplate,
              !workout.isDeleted,
              !workout.isArchived else {
            throw WorkoutRepositoryError.workoutNotFound
        }

        guard let session = try context.existingObject(with: input.id) as? WorkoutSession,
              !session.isDeleted,
              session.workoutTemplate == workout,
              session.endedAt == nil else {
            throw WorkoutRepositoryError.sessionNotFound
        }
        session.startedAt = input.startedAt
        session.endedAt = input.endedAt
        session.durationSeconds = Int64(max(0, input.endedAt.timeIntervalSince(input.startedAt)))
        session.rating = Int16(input.rating)
        session.syncState = "pendingCreate"
        session.workoutTemplate = workout
        session.user = workout.user

        try replaceContents(of: session, with: input.exercises, completedAt: input.endedAt)

        workout.updatedAt = input.endedAt
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func replaceContents(
        of session: WorkoutSession,
        with inputs: [CompletedSessionExercise],
        completedAt: Date
    ) throws {
        let existingExercises = session.sessionExercises?.array as? [SessionExercise] ?? []
        session.sessionExercises = NSOrderedSet()
        existingExercises.forEach(context.delete)

        var completedSetCount = 0
        var totalSetCount = 0
        var totalVolume = Decimal.zero
        let sessionExercises = try inputs.enumerated().map { position, inputExercise in
            guard let exercise = try context.existingObject(with: inputExercise.exerciseID) as? Exercise else {
                throw WorkoutRepositoryError.exerciseNotFound
            }
            let sessionExercise = SessionExercise(context: context)
            sessionExercise.clientUUID = UUID()
            sessionExercise.position = Int32(position)
            sessionExercise.syncState = "pendingCreate"
            sessionExercise.exercise = exercise
            sessionExercise.session = session

            let sets = inputExercise.sets.map { inputSet in
                let set = SessionSet(context: context)
                set.clientUUID = UUID()
                set.setNumber = Int32(inputSet.number)
                set.reps = Int32(inputSet.reps)
                set.timeSeconds = inputSet.timeSeconds
                set.distance = NSDecimalNumber(decimal: inputSet.distance)
                let weightInPounds = selectedWeightUnit.pounds(fromDisplayed: inputSet.weight)
                set.weight = NSDecimalNumber(decimal: weightInPounds)
                set.completed = inputSet.completed
                set.completedAt = inputSet.completed ? completedAt : nil
                set.isWarmup = false
                set.syncState = "pendingCreate"
                set.sessionExercise = sessionExercise
                totalSetCount += 1
                if inputSet.completed {
                    completedSetCount += 1
                    totalVolume += Decimal(inputSet.reps) * weightInPounds
                }
                return set
            }
            sessionExercise.sets = NSOrderedSet(array: sets)
            return sessionExercise
        }
        session.sessionExercises = NSOrderedSet(array: sessionExercises)
        session.volumeWeight = NSDecimalNumber(decimal: totalVolume)
        session.percentCompleted = totalSetCount == 0
            ? 0
            : Double(completedSetCount) / Double(totalSetCount) * 100
    }

    func calculateImprovements(for inputs: [CompletedSessionExercise]) throws -> [ExerciseImprovementSummary] {
        try inputs.map { input in
            guard let exercise = try context.existingObject(with: input.exerciseID) as? Exercise else {
                throw WorkoutRepositoryError.exerciseNotFound
            }
            let currentSets = input.sets.filter(\.completed).map { set in
                CompletedSessionSet(
                    number: set.number,
                    reps: set.reps,
                    timeSeconds: set.timeSeconds,
                    distance: set.distance,
                    weight: selectedWeightUnit.pounds(fromDisplayed: set.weight),
                    completed: set.completed
                )
            }
            let configuration = ExerciseConfiguration(storageValue: exercise.trackingType ?? "")
            let historicalOccurrences = (exercise.sessionExercises as? Set<SessionExercise> ?? [])
                .filter { $0.session?.endedAt != nil }
                .sorted { ($0.session?.endedAt ?? .distantPast) > ($1.session?.endedAt ?? .distantPast) }
            let lifetimeSets = historicalOccurrences.flatMap(completedSets)
            let previousSets = historicalOccurrences.first.map(completedSets) ?? []

            return ExerciseImprovementSummary(
                id: exercise.objectID,
                exerciseName: exercise.name ?? "Untitled Exercise",
                lifetime: improvementMetrics(
                    current: currentSets,
                    historical: lifetimeSets,
                    configuration: configuration
                ),
                previous: improvementMetrics(
                    current: currentSets,
                    historical: previousSets,
                    configuration: configuration
                )
            )
        }
    }

    private func completedSets(from occurrence: SessionExercise) -> [CompletedSessionSet] {
        (occurrence.sets?.array as? [SessionSet] ?? [])
            .filter(\.completed)
            .map {
                CompletedSessionSet(
                    number: Int($0.setNumber),
                    reps: Int($0.reps),
                    timeSeconds: $0.timeSeconds,
                    distance: $0.distance as Decimal? ?? 0,
                    weight: $0.weight as Decimal? ?? 0,
                    completed: true
                )
            }
    }

    private func improvementMetrics(
        current: [CompletedSessionSet],
        historical: [CompletedSessionSet],
        configuration: ExerciseConfiguration
    ) -> ExerciseImprovementMetrics {
        let usesAssistance = configuration.difficultyType == .assistedWeight
        let primaryTitle: String
        switch configuration.repType {
        case .reps: primaryTitle = "Max Reps"
        case .time: primaryTitle = "Max Time"
        case .distance: primaryTitle = "Max Distance"
        }

        guard !current.isEmpty else {
            return ExerciseImprovementMetrics(metrics: metricTitles(for: configuration).map {
                ImprovementMetric(title: $0, displayValue: "–", trend: .firstEntry)
            })
        }

        let currentResistance = usesAssistance
            ? current.map(\.weight).min() ?? 0
            : current.map(\.weight).max() ?? 0
        let currentAtResistance = current.filter { $0.weight == currentResistance }
        let historicalAtResistance = historical.filter { $0.weight == currentResistance }
        let currentPerformance = maximumPerformance(in: currentAtResistance, repType: configuration.repType)
        let historicalPerformance = maximumPerformance(in: historicalAtResistance, repType: configuration.repType)
        guard let currentPerformance else {
            return ExerciseImprovementMetrics(metrics: metricTitles(for: configuration).map {
                ImprovementMetric(title: $0, displayValue: "–", trend: .firstEntry)
            })
        }
        let historicalResistance = usesAssistance
            ? historical.map(\.weight).min()
            : historical.map(\.weight).max()

        var metrics = [ImprovementMetric(
            title: primaryTitle,
            displayValue: performanceComparisonText(
                current: currentPerformance,
                historical: historicalPerformance,
                resistance: configuration.difficultyType == .bodyweight ? nil : currentResistance,
                repType: configuration.repType
            ),
            trend: trend(currentPerformance, comparedWith: historicalPerformance)
        )]

        if configuration.difficultyType != .bodyweight {
            metrics.append(ImprovementMetric(
                title: usesAssistance ? "Min Assistance" : "Max Weight",
                displayValue: comparisonText(current: currentResistance, historical: historicalResistance),
                trend: usesAssistance
                    ? inverseTrend(currentResistance, comparedWith: historicalResistance)
                    : trend(currentResistance, comparedWith: historicalResistance)
            ))
        }

        if configuration.repType == .reps && configuration.difficultyType == .weighted {
            let currentVolume = current.map { Decimal($0.reps) * $0.weight }.max() ?? 0
            let historicalVolume = historical.map { Decimal($0.reps) * $0.weight }.max()
            metrics.append(ImprovementMetric(
                title: "Volume Weight",
                displayValue: comparisonText(current: currentVolume, historical: historicalVolume),
                trend: trend(currentVolume, comparedWith: historicalVolume)
            ))
        }

        return ExerciseImprovementMetrics(metrics: metrics)
    }

    private func metricTitles(for configuration: ExerciseConfiguration) -> [String] {
        let primary: String
        switch configuration.repType {
        case .reps: primary = "Max Reps"
        case .time: primary = "Max Time"
        case .distance: primary = "Max Distance"
        }
        guard configuration.difficultyType != .bodyweight else { return [primary] }
        let resistance = configuration.difficultyType == .assistedWeight ? "Min Assistance" : "Max Weight"
        guard configuration.repType == .reps,
              configuration.difficultyType == .weighted else { return [primary, resistance] }
        return [primary, resistance, "Volume Weight"]
    }

    private func maximumPerformance(
        in sets: [CompletedSessionSet],
        repType: ExerciseRepType
    ) -> Decimal? {
        switch repType {
        case .reps: sets.map { Decimal($0.reps) }.max()
        case .time: sets.map { Decimal($0.timeSeconds) }.max()
        case .distance: sets.map(\.distance).max()
        }
    }

    private func performanceComparisonText(
        current: Decimal?,
        historical: Decimal?,
        resistance: Decimal?,
        repType: ExerciseRepType
    ) -> String {
        guard let current else { return "–" }
        let currentText = performanceText(current, repType: repType)
        let comparison = historical.map { "\(performanceText($0, repType: repType)) → \(currentText)" } ?? currentText
        return resistance.map { "\(comparison) @ \(weightText($0))" } ?? comparison
    }

    private func performanceText(_ value: Decimal, repType: ExerciseRepType) -> String {
        guard repType == .time else { return decimalText(value) }
        let seconds = max(0, NSDecimalNumber(decimal: value).intValue)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func trend<T: Comparable>(_ current: T, comparedWith historical: T?) -> ImprovementTrend {
        guard let historical else { return .firstEntry }
        if current > historical { return .improved }
        if current < historical { return .regressed }
        return .maintained
    }

    private func inverseTrend<T: Comparable>(_ current: T, comparedWith historical: T?) -> ImprovementTrend {
        guard let historical else { return .firstEntry }
        if current < historical { return .improved }
        if current > historical { return .regressed }
        return .maintained
    }

    private func decimalText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).doubleValue.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func weightText(_ pounds: Decimal) -> String {
        "\(decimalText(selectedWeightUnit.displayed(fromPounds: pounds))) \(selectedWeightUnit.rawValue)"
    }

    private func comparisonText(current: Decimal, historical: Decimal?) -> String {
        guard let historical else { return weightText(current) }
        return "\(weightText(historical)) → \(weightText(current))"
    }

    private func latestSessionSets(for exercise: Exercise) -> [SessionSet] {
        let occurrences = (exercise.sessionExercises as? Set<SessionExercise> ?? [])
            .filter { $0.session?.endedAt != nil }
            .sorted {
                ($0.session?.endedAt ?? .distantPast) > ($1.session?.endedAt ?? .distantPast)
            }
        guard let latest = occurrences.first else { return [] }
        return (latest.sets?.array as? [SessionSet] ?? [])
            .sorted { $0.setNumber < $1.setNumber }
    }

    func fetchAvailableExercises() throws -> [ExerciseListItem] {
        let request = Exercise.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        request.predicate = NSPredicate(format: "isArchived == NO")
        return try context.fetch(request).map { exercise in
            let configuration = ExerciseConfiguration(storageValue: exercise.trackingType ?? "")
            return ExerciseListItem(
                id: exercise.objectID,
                name: exercise.name ?? "Untitled Exercise",
                primaryMuscleColorHex: exercise.primaryMuscle?.colorHex ?? "8AC5FF",
                repType: configuration.repType,
                difficultyType: configuration.difficultyType,
                targetRestSeconds: Int(exercise.targetRestSeconds)
            )
        }
    }

    func fetchTags() throws -> [TagItem] {
        let request = Tag.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        var tags = try context.fetch(request)
        let existingNames = Set(tags.compactMap(\.name).map { $0.lowercased() })
        let missingNames = Self.defaultTags.filter { !existingNames.contains($0.lowercased()) }

        if !missingNames.isEmpty {
            let insertedTags = missingNames.map { name in
                let tag = Tag(context: context)
                tag.clientUUID = UUID()
                tag.name = name
                tag.syncState = "synced"
                return tag
            }
            tags.append(contentsOf: insertedTags)
            do {
                try context.save()
            } catch {
                insertedTags.forEach(context.delete)
                throw error
            }
        }

        return tags
            .sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
            .map { TagItem(id: $0.objectID, name: $0.name ?? "Untitled") }
    }

    @discardableResult
    func createTag(named rawName: String) throws -> TagItem {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WorkoutRepositoryError.tagNameRequired }

        let request = Tag.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "name =[c] %@", name)
        if let existing = try context.fetch(request).first {
            return TagItem(id: existing.objectID, name: existing.name ?? name)
        }

        let tag = Tag(context: context)
        tag.clientUUID = UUID()
        tag.name = name
        tag.syncState = "pendingCreate"
        do {
            try context.save()
        } catch {
            context.delete(tag)
            throw error
        }
        return TagItem(id: tag.objectID, name: name)
    }

    @discardableResult
    func createWorkout(_ input: NewWorkout) throws -> WorkoutListItem {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WorkoutRepositoryError.nameRequired }
        guard !input.exerciseIDs.isEmpty else { throw WorkoutRepositoryError.exerciseRequired }

        let workout = WorkoutTemplate(context: context)
        workout.clientUUID = UUID()
        workout.createdAt = Date()
        workout.updatedAt = Date()
        workout.name = name
        workout.syncState = "pendingCreate"
        workout.user = user

        let exercises = try input.exerciseIDs.enumerated().map { position, id in
            guard let exercise = try context.existingObject(with: id) as? Exercise else {
                throw WorkoutRepositoryError.exerciseNotFound
            }
            let item = TemplateExercise(context: context)
            item.clientUUID = UUID()
            item.position = Int32(position)
            item.syncState = "pendingCreate"
            item.exercise = exercise
            item.workoutTemplate = workout
            let alternateIDs = input.alternateExerciseIDsByExerciseID[id] ?? []
            let alternates = try alternateIDs.compactMap { alternateID in
                try context.existingObject(with: alternateID) as? Exercise
            }
            item.alternateExercises = Set(alternates) as NSSet

            let plannedSets = (input.plannedSetsByExerciseID[id] ?? []).enumerated().map { setIndex, input in
                let set = TemplatePlannedSet(context: context)
                set.clientUUID = UUID()
                set.setNumber = Int32(setIndex + 1)
                set.syncState = "pendingCreate"
                set.plannedReps = input.reps.map(Int32.init) ?? 0
                set.plannedTimeSeconds = input.timeSeconds ?? 0
                set.plannedDistance = input.distance as NSDecimalNumber?
                set.plannedWeight = input.weight.map {
                    NSDecimalNumber(decimal: selectedWeightUnit.pounds(fromDisplayed: $0))
                }
                set.templateExercise = item
                return set
            }
            item.plannedSets = NSOrderedSet(array: plannedSets)
            return item
        }
        workout.templateExercises = NSOrderedSet(array: exercises)

        let tags = try input.selectedTagIDs.compactMap { try context.existingObject(with: $0) as? Tag }
        workout.tags = Set(tags) as NSSet

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return WorkoutListItem(
            id: workout.objectID,
            name: name,
            exerciseCount: exercises.count,
            updatedAt: workout.updatedAt ?? Date(),
            tags: tags.compactMap { tag in
                guard let name = tag.name else { return nil }
                return WorkoutTagSummary(name: name, color: TagColor(name: name))
            },
            statistics: .empty
        )
    }

    private func workoutStatistics(from sessions: [WorkoutSession]) -> WorkoutStatistics {
        guard !sessions.isEmpty else { return .empty }

        func mean(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }

        let durations = sessions.compactMap { $0.durationSeconds > 0 ? Double($0.durationSeconds) / 60 : nil }
        let volumes = sessions.compactMap { ($0.volumeWeight as Decimal?).map { NSDecimalNumber(decimal: $0).doubleValue } }
        return WorkoutStatistics(
            lastUsed: sessions.compactMap(\.endedAt).max(),
            meanDurationMinutes: mean(durations),
            meanVolume: mean(volumes).map {
                selectedWeightUnit.displayed(fromPounds: Decimal($0))
            },
            meanRestSeconds: mean(sessions.compactMap { $0.averageRestSeconds > 0 ? $0.averageRestSeconds : nil }),
            meanIntensity: mean(sessions.compactMap { $0.estimatedIntensity > 0 ? $0.estimatedIntensity : nil }),
            meanPercentCompleted: mean(sessions.compactMap { $0.percentCompleted > 0 ? $0.percentCompleted : nil })
        )
    }

    private static let defaultTags = [
        "Upper",
        "Lower",
        "Core",
        "Push",
        "Pull",
        "Legs",
        "Back",
        "Chest",
        "Hypertrophy",
        "Strength",
        "Plyometrics",
        "Calisthenics",
        "Circuit",
        "Beginner",
        "Intermediate",
        "Advanced",
        "Endurance",
        "Flexibility",
        "Stability",
        "Cardio",
        "Functional",
        "Bodyweight"
    ]
}

enum WorkoutRepositoryError: LocalizedError {
    case nameRequired, exerciseRequired, exerciseNotFound, tagNameRequired, workoutNotFound, sessionNotFound

    var errorDescription: String? {
        switch self {
        case .nameRequired: "Enter a workout name."
        case .exerciseRequired: "Add at least one exercise."
        case .exerciseNotFound: "One of the selected exercises is no longer available."
        case .tagNameRequired: "Enter a tag name."
        case .workoutNotFound: "This workout is no longer available."
        case .sessionNotFound: "This workout session is no longer available."
        }
    }
}

@MainActor
final class CoreDataExerciseRepository: ExerciseRepository {
    private let context: NSManagedObjectContext
    private let user: User

    init(context: NSManagedObjectContext, user: User) {
        self.context = context
        self.user = user
    }

    func fetchExercises() throws -> [ExerciseListItem] {
        let request = Exercise.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        request.predicate = NSPredicate(format: "isArchived == NO")

        return try context.fetch(request).map { exercise in
            let configuration = ExerciseConfiguration(storageValue: exercise.trackingType ?? "")
            return ExerciseListItem(
                id: exercise.objectID,
                name: exercise.name ?? "Untitled Exercise",
                primaryMuscleColorHex: exercise.primaryMuscle?.colorHex ?? "8AC5FF",
                repType: configuration.repType,
                difficultyType: configuration.difficultyType,
                targetRestSeconds: Int(exercise.targetRestSeconds)
            )
        }
    }

    func fetchExercise(id: NSManagedObjectID) throws -> ExerciseDetail {
        guard let exercise = try context.existingObject(with: id) as? Exercise,
              !exercise.isDeleted,
              !exercise.isArchived else {
            throw ExerciseRepositoryError.exerciseNotFound
        }

        let configuration = ExerciseConfiguration(storageValue: exercise.trackingType ?? "")
        return ExerciseDetail(
            id: exercise.objectID,
            name: exercise.name ?? "Untitled Exercise",
            repType: configuration.repType,
            difficultyType: configuration.difficultyType,
            targetRestSeconds: Int(exercise.targetRestSeconds),
            primaryMuscle: exercise.primaryMuscle?.name ?? "Not set",
            secondaryMuscles: (exercise.secondaryMuscles as? Set<Muscle> ?? [])
                .compactMap(\.name)
                .sorted()
        )
    }

    func fetchMuscles() throws -> [MuscleItem] {
        let request = Muscle.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        var muscles = try context.fetch(request)

        let existingNames = Set(muscles.compactMap(\.name))
        let missingNames = Self.defaultMuscles.filter { !existingNames.contains($0) }
        if !missingNames.isEmpty {
            let insertedMuscles = missingNames.map { name in
                let muscle = Muscle(context: context)
                muscle.serverID = UUID()
                muscle.name = name
                muscle.colorHex = "8AC5FF"
                return muscle
            }
            muscles.append(contentsOf: insertedMuscles)
            do {
                try context.save()
            } catch {
                insertedMuscles.forEach(context.delete)
                throw error
            }
        }

        return muscles.sorted { ($0.name ?? "") < ($1.name ?? "") }.map {
            MuscleItem(
                id: $0.objectID,
                name: $0.name ?? "Unknown",
                colorHex: $0.colorHex ?? "8AC5FF"
            )
        }
    }

    @discardableResult
    func createExercise(_ input: NewExercise) throws -> ExerciseListItem {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ExerciseRepositoryError.nameRequired }
        guard let primary = try context.existingObject(with: input.primaryMuscleID) as? Muscle else {
            throw ExerciseRepositoryError.primaryMuscleRequired
        }

        let exercise = Exercise(context: context)
        exercise.clientUUID = UUID()
        exercise.createdAt = Date()
        exercise.name = name
        exercise.trackingType = ExerciseConfiguration(
            repType: input.repType,
            difficultyType: input.difficultyType
        ).storageValue
        exercise.targetRestSeconds = Int32(input.targetRestSeconds)
        exercise.primaryMuscle = primary
        exercise.owner = user
        exercise.syncState = "pendingCreate"
        exercise.secondaryMuscles = Set(try input.secondaryMuscleIDs.compactMap {
            try context.existingObject(with: $0) as? Muscle
        }) as NSSet
        do {
            try context.save()
        } catch {
            context.delete(exercise)
            throw error
        }

        return ExerciseListItem(
            id: exercise.objectID,
            name: name,
            primaryMuscleColorHex: primary.colorHex ?? "8AC5FF",
            repType: input.repType,
            difficultyType: input.difficultyType,
            targetRestSeconds: input.targetRestSeconds
        )
    }

    private static let defaultMuscles = [
        "Abdominals",
        "Abductors",
        "Adductors",
        "Biceps",
        "Calves",
        "Forearm Extensors",
        "Forearm Flexors",
        "Front Deltoid",
        "Gluteus maximus",
        "Hamstrings",
        "Lateral Deltoid",
        "Lats",
        "Lower Back",
        "Lower Chest",
        "Lower Traps",
        "Middle Traps",
        "Obliques",
        "Quads",
        "Rear Deltoid",
        "Triceps",
        "Upper Chest",
        "Upper Traps"
    ]
}

enum ExerciseRepositoryError: LocalizedError {
    case exerciseNotFound
    case nameRequired
    case primaryMuscleRequired

    var errorDescription: String? {
        switch self {
        case .exerciseNotFound: "Exercise not found."
        case .nameRequired: "Enter an exercise name."
        case .primaryMuscleRequired: "Select a primary muscle."
        }
    }
}
