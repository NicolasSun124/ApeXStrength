import CoreData
import Foundation

enum SyncServiceError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The sync server returned an invalid response."
        case let .server(message): return message
        }
    }
}

/// Uploads a complete, self-contained snapshot. Calls are coalesced so several
/// saves made by one UI action never create overlapping requests.
@MainActor
final class APISyncService: SyncService {
    private let context: NSManagedObjectContext
    private let user: User
    private let settings: any SettingsService
    private let baseURL: URL
    private let session: URLSession
    private let token: () -> String?
    private var runningTask: Task<Void, Error>?

    init(
        context: NSManagedObjectContext,
        user: User,
        settings: any SettingsService,
        baseURL: URL,
        session: URLSession = .shared,
        token: @escaping () -> String?
    ) {
        self.context = context
        self.user = user
        self.settings = settings
        self.baseURL = baseURL
        self.session = session
        self.token = token
    }

    func syncIfNeeded() async throws {
        if let runningTask { try await runningTask.value }
        let task = Task { @MainActor in try await performSync() }
        runningTask = task
        defer { runningTask = nil }
        try await task.value
    }

    private func performSync() async throws {
        guard let token = token() else { return }
        let isBootstrap = user.syncProtocolVersion < 2
        let pendingChanges = try changes(forceAll: isBootstrap)
        markInFlight(pendingChanges)
        let body = try JSONSerialization.data(withJSONObject: [
            "cursor": user.syncCursor,
            "changes": pendingChanges
        ], options: [.sortedKeys])
        var request = URLRequest(url: baseURL.appendingPathComponent("sync"))
        request.httpMethod = "PUT"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch { restoreInFlight(); throw error }
        guard let response = response as? HTTPURLResponse else { restoreInFlight(); throw SyncServiceError.invalidResponse }
        guard 200..<300 ~= response.statusCode else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            restoreInFlight(); throw SyncServiceError.server(message ?? "Unable to sync your data.")
        }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accepted = payload["accepted"] as? [[String: Any]] else {
            restoreInFlight(); throw SyncServiceError.invalidResponse
        }
        markRecordsSynced(accepted, sentChanges: pendingChanges)
        if let remote = payload["changes"] as? [[String: Any]], let cursor = payload["cursor"] as? NSNumber {
            let conflicts = payload["conflicts"] as? [[String: Any]] ?? []
            try applyRemoteChanges(remote + conflicts)
            user.syncCursor = cursor.int64Value
            if isBootstrap { user.syncProtocolVersion = 2 }
            try context.save()
        }
    }

    private func changes(forceAll: Bool) throws -> [[String: Any]] {
        let pending = forceAll ? NSPredicate(value: true) : NSPredicate(format: "syncState != %@", "synced")
        var output: [[String: Any]] = []
        func add(_ entity: String, _ uuid: String, _ state: String?, _ data: [String: Any]) {
            output.append(["entity": entity, "client_uuid": uuid,
                           "operation": state == "pendingDelete" ? "delete" : "upsert", "data": data])
        }
        if forceAll || settings.needsSync {
            let value = settings.load()
            add("settings", "settings", "pendingUpdate", ["weight_unit": value.weightUnit, "distance_unit": value.distanceUnit,
                "rest_timer_notifications_enabled": value.restTimerNotificationsEnabled])
        }
        for item in try fetch(Exercise.self, predicate: pending) {
            add("exercise", id(item.clientUUID, item.serverID), item.syncState,
                ["name": item.name ?? "", "created_at": iso(item.createdAt), "is_archived": item.isArchived,
                 "tracking_type": item.trackingType ?? "", "target_rest_seconds": item.targetRestSeconds,
                 "primary_muscle_id": item.primaryMuscle?.serverID.uuidString ?? "",
                 "primary_muscle_name": item.primaryMuscle?.name ?? "Unknown", "primary_muscle_color": item.primaryMuscle?.colorHex ?? "8AC5FF",
                 "secondary_muscle_names": (item.secondaryMuscles as? Set<Muscle> ?? []).compactMap(\.name).sorted(),
                 "secondary_muscle_ids": (item.secondaryMuscles as? Set<Muscle> ?? []).map { $0.serverID.uuidString }.sorted()])
        }
        for item in try fetch(Tag.self, predicate: pending) {
            add("tag", id(item.clientUUID, item.serverID), item.syncState, ["name": item.name ?? ""])
        }
        for item in try fetch(WorkoutTemplate.self, predicate: pending) {
            add("workout", item.clientUUID.uuidString, item.syncState,
                ["name": item.name ?? "", "created_at": iso(item.createdAt), "updated_at": iso(item.updatedAt),
                 "is_archived": item.isArchived, "tag_ids": (item.tags as? Set<Tag> ?? []).map { id($0.clientUUID, $0.serverID) }.sorted()])
        }
        for item in try fetch(TemplateExercise.self, predicate: pending) {
            add("template_exercise", item.clientUUID.uuidString, item.syncState,
                ["workout_id": item.workoutTemplate?.clientUUID.uuidString ?? "", "exercise_id": id(item.exercise?.clientUUID, item.exercise?.serverID),
                 "position": item.position, "alternate_exercise_ids": (item.alternateExercises as? Set<Exercise> ?? []).map { id($0.clientUUID, $0.serverID) }.sorted()])
        }
        for item in try fetch(TemplatePlannedSet.self, predicate: pending) {
            add("template_set", item.clientUUID.uuidString, item.syncState,
                ["template_exercise_id": item.templateExercise?.clientUUID.uuidString ?? "", "number": item.setNumber, "warmup": item.isWarmup,
                 "reps": value(item.plannedReps), "time_seconds": value(item.plannedTimeSeconds), "distance": decimal(item.plannedDistance), "weight": decimal(item.plannedWeight)])
        }
        for item in try fetch(WorkoutSession.self, predicate: pending) { add("workout_session", item.clientUUID.uuidString, item.syncState, sessionJSON(item)) }
        for item in try fetch(SessionExercise.self, predicate: pending) {
            add("session_exercise", item.clientUUID.uuidString, item.syncState,
                ["session_id": item.session?.clientUUID.uuidString ?? "", "exercise_id": id(item.exercise?.clientUUID, item.exercise?.serverID), "position": item.position,
                 "name": item.snapshotExerciseName ?? "", "tracking_type": item.snapshotTrackingType ?? "", "difficulty_type": item.snapshotDifficultyType ?? "",
                 "primary_muscle_name": item.snapshotPrimaryMuscleName ?? "", "primary_muscle_color": item.snapshotPrimaryMuscleColorHex ?? "",
                 "target_rest_seconds": item.snapshotTargetRestSeconds ?? NSNull()])
        }
        for item in try fetch(SessionSet.self, predicate: pending) {
            add("session_set", item.clientUUID.uuidString, item.syncState,
                ["session_exercise_id": item.sessionExercise?.clientUUID.uuidString ?? "", "number": item.setNumber, "completed": item.completed,
                 "completed_at": item.completedAt.map(iso) ?? NSNull(), "warmup": item.isWarmup, "reps": value(item.reps),
                 "time_seconds": value(item.timeSeconds), "distance": decimal(item.distance), "weight": decimal(item.weight), "pace": value(item.pace)])
        }
        for item in try fetch(SyncTombstone.self, predicate: NSPredicate(value: true)) {
            output.append(["entity": item.entityType, "client_uuid": item.clientUUID.uuidString, "operation": "delete", "data": [:]])
        }
        return output
    }

    private func workoutJSON(_ workout: WorkoutTemplate) -> [String: Any] {
        let items = (workout.templateExercises?.array as? [TemplateExercise] ?? []).sorted { $0.position < $1.position }
        return ["id": workout.clientUUID.uuidString, "name": workout.name ?? "", "created_at": iso(workout.createdAt),
                "updated_at": iso(workout.updatedAt), "is_archived": workout.isArchived,
                "tag_ids": (workout.tags as? Set<Tag> ?? []).map { id($0.clientUUID, $0.serverID) }.sorted(),
                "exercises": items.map { item in
                    ["id": item.clientUUID.uuidString, "exercise_id": id(item.exercise?.clientUUID, item.exercise?.serverID), "position": item.position,
                     "alternate_exercise_ids": (item.alternateExercises as? Set<Exercise> ?? []).map { id($0.clientUUID, $0.serverID) }.sorted(),
                     "sets": (item.plannedSets?.array as? [TemplatePlannedSet] ?? []).map { set in
                        ["id": set.clientUUID.uuidString, "number": set.setNumber, "warmup": set.isWarmup,
                         "reps": value(set.plannedReps), "time_seconds": value(set.plannedTimeSeconds),
                         "distance": decimal(set.plannedDistance), "weight": decimal(set.plannedWeight)] as [String: Any]
                     }] as [String: Any]
                }] as [String: Any]
    }

    private func sessionJSON(_ session: WorkoutSession) -> [String: Any] {
        ["id": session.clientUUID.uuidString, "workout_id": session.workoutTemplate.map { $0.clientUUID.uuidString } ?? NSNull(),
         "started_at": iso(session.startedAt), "ended_at": session.endedAt.map(iso) ?? NSNull(), "duration_seconds": session.durationSeconds,
         "rating": session.rating, "note": session.note ?? NSNull(), "percent_completed": session.percentCompleted,
         "volume_weight": decimal(session.volumeWeight), "average_rest_seconds": value(session.averageRestSeconds),
         "estimated_intensity": value(session.estimatedIntensity)]
    }

    private func fetch<T: NSManagedObject>(_ type: T.Type, predicate: NSPredicate) throws -> [T] {
        let request = NSFetchRequest<T>(entityName: String(describing: type)); request.predicate = predicate
        return try context.fetch(request)
    }
    private func markRecordsSynced(_ accepted: [[String: Any]], sentChanges: [[String: Any]]) {
        let names = ["exercise": "Exercise", "tag": "Tag", "workout": "WorkoutTemplate", "template_exercise": "TemplateExercise",
                     "template_set": "TemplatePlannedSet", "workout_session": "WorkoutSession", "session_exercise": "SessionExercise", "session_set": "SessionSet"]
        for acknowledgement in accepted {
            guard let entity = acknowledgement["entity"] as? String else { continue }
            if entity == "settings" {
                if let sent = sentChanges.first(where: { $0["entity"] as? String == "settings" })?["data"] as? [String: Any] {
                    let current = settings.load()
                    if sent["weight_unit"] as? String == current.weightUnit,
                       sent["distance_unit"] as? String == current.distanceUnit,
                       sent["rest_timer_notifications_enabled"] as? Bool == current.restTimerNotificationsEnabled { settings.markSynced() }
                }
                continue
            }
            if let uuidString = acknowledgement["client_uuid"] as? String, let uuid = UUID(uuidString: uuidString) {
                let tombstones = NSFetchRequest<SyncTombstone>(entityName: "SyncTombstone")
                tombstones.predicate = NSPredicate(format: "clientUUID == %@ AND entityType == %@", uuid as CVarArg, entity)
                (try? context.fetch(tombstones))?.forEach(context.delete)
            }
            guard let uuidString = acknowledgement["client_uuid"] as? String, let uuid = UUID(uuidString: uuidString), let name = names[entity] else { continue }
            let request = NSFetchRequest<NSManagedObject>(entityName: name)
            request.predicate = NSPredicate(format: "clientUUID == %@", uuid as CVarArg)
            (try? context.fetch(request))?.filter { $0.value(forKey: "syncState") as? String == "syncing" }.forEach { $0.setValue("synced", forKey: "syncState") }
        }
        let sessions = try? fetch(WorkoutSession.self, predicate: NSPredicate(format: "user == %@", user))
        sessions?.forEach { $0.syncedAt = Date() }
        try? context.save()
    }

    private func markInFlight(_ changes: [[String: Any]]) {
        let names = ["exercise": "Exercise", "tag": "Tag", "workout": "WorkoutTemplate", "template_exercise": "TemplateExercise", "template_set": "TemplatePlannedSet", "workout_session": "WorkoutSession", "session_exercise": "SessionExercise", "session_set": "SessionSet"]
        for change in changes {
            guard let entity = change["entity"] as? String, let name = names[entity], let raw = change["client_uuid"] as? String, let uuid = UUID(uuidString: raw) else { continue }
            let request = NSFetchRequest<NSManagedObject>(entityName: name); request.predicate = NSPredicate(format: "clientUUID == %@", uuid as CVarArg)
            (try? context.fetch(request))?.forEach { $0.setValue("syncing", forKey: "syncState") }
        }
        try? context.save()
    }
    private func restoreInFlight() {
        for name in ["Exercise", "Tag", "WorkoutTemplate", "TemplateExercise", "TemplatePlannedSet", "WorkoutSession", "SessionExercise", "SessionSet"] {
            let request = NSFetchRequest<NSManagedObject>(entityName: name); request.predicate = NSPredicate(format: "syncState == %@", "syncing")
            (try? context.fetch(request))?.forEach { $0.setValue("pendingUpdate", forKey: "syncState") }
        }
        try? context.save()
    }

    private func applyRemoteChanges(_ changes: [[String: Any]]) throws {
        for change in changes {
            guard let entity = change["entity"] as? String,
                  let uuidString = change["client_uuid"] as? String else { continue }
            let operation = change["operation"] as? String ?? "upsert"
            if entity == "settings", let data = change["data"] as? [String: Any] {
                settings.applyRemote(AppSettings(
                    weightUnit: data["weight_unit"] as? String ?? "lbs",
                    distanceUnit: data["distance_unit"] as? String ?? "km",
                    restTimerNotificationsEnabled: data["rest_timer_notifications_enabled"] as? Bool ?? true
                ))
                continue
            }
            guard let uuid = UUID(uuidString: uuidString) else { continue }
            if operation == "delete" { deleteRemote(entity: entity, uuid: uuid); continue }
            if hasPendingLocal(entity: entity, uuid: uuid) { continue }
            guard let data = change["data"] as? [String: Any] else { continue }
            switch entity {
            case "exercise":
                let item = try object(Exercise.self, uuid: uuid)
                item.clientUUID = uuid; item.owner = user; item.name = data["name"] as? String
                item.createdAt = date(data["created_at"]) ?? Date(); item.isArchived = data["is_archived"] as? Bool ?? false
                item.trackingType = data["tracking_type"] as? String; item.targetRestSeconds = Int32(number(data["target_rest_seconds"]))
                item.primaryMuscle = try muscle(named: data["primary_muscle_name"] as? String ?? "Unknown", color: data["primary_muscle_color"] as? String ?? "8AC5FF")
                let secondary = try (data["secondary_muscle_names"] as? [String] ?? []).map { try muscle(named: $0, color: "8AC5FF") }
                item.secondaryMuscles = Set(secondary) as NSSet; item.syncState = "synced"
            case "tag":
                let item = try object(Tag.self, uuid: uuid); item.clientUUID = uuid; item.owner = user; item.name = data["name"] as? String; item.syncState = "synced"
            case "workout":
                let item = try object(WorkoutTemplate.self, uuid: uuid); item.clientUUID = uuid; item.user = user; item.name = data["name"] as? String
                item.createdAt = date(data["created_at"]) ?? Date(); item.updatedAt = date(data["updated_at"]) ?? Date()
                item.isArchived = data["is_archived"] as? Bool ?? false; item.syncState = "synced"
                item.tags = Set((data["tag_ids"] as? [String] ?? []).compactMap(UUID.init(uuidString:)).compactMap { try? existing(Tag.self, uuid: $0) }) as NSSet
            case "template_exercise":
                let item = try object(TemplateExercise.self, uuid: uuid); item.clientUUID = uuid; item.position = Int32(number(data["position"])); item.syncState = "synced"
                item.workoutTemplate = try related(WorkoutTemplate.self, string: data["workout_id"]); item.exercise = try related(Exercise.self, string: data["exercise_id"])
                item.alternateExercises = Set((data["alternate_exercise_ids"] as? [String] ?? []).compactMap(UUID.init(uuidString:)).compactMap { try? existing(Exercise.self, uuid: $0) }) as NSSet
            case "template_set":
                let item = try object(TemplatePlannedSet.self, uuid: uuid); item.clientUUID = uuid; item.syncState = "synced"
                item.templateExercise = try related(TemplateExercise.self, string: data["template_exercise_id"]); item.setNumber = Int32(number(data["number"])); item.isWarmup = data["warmup"] as? Bool ?? false
                item.plannedReps = Int32(number(data["reps"])); item.plannedTimeSeconds = double(data["time_seconds"]); item.plannedDistance = decimalNumber(data["distance"]); item.plannedWeight = decimalNumber(data["weight"])
            case "workout_session": try applySession(uuid, data)
            case "session_exercise": try applySessionExercise(uuid, data)
            case "session_set": try applySessionSet(uuid, data)
            default: break
            }
        }
    }

    private func applySession(_ uuid: UUID, _ data: [String: Any]) throws {
        let item = try object(WorkoutSession.self, uuid: uuid); item.clientUUID = uuid; item.user = user; item.syncState = "synced"
        item.workoutTemplate = try related(WorkoutTemplate.self, string: data["workout_id"]); item.startedAt = date(data["started_at"]) ?? Date(); item.endedAt = date(data["ended_at"])
        item.durationSeconds = Int64(number(data["duration_seconds"])); item.rating = Int16(number(data["rating"])); item.note = data["note"] as? String
        item.percentCompleted = double(data["percent_completed"]); item.volumeWeight = decimalNumber(data["volume_weight"])
        item.averageRestSeconds = double(data["average_rest_seconds"]); item.estimatedIntensity = double(data["estimated_intensity"]); item.syncedAt = Date()
    }
    private func applySessionExercise(_ uuid: UUID, _ data: [String: Any]) throws {
        let item = try object(SessionExercise.self, uuid: uuid); item.clientUUID = uuid; item.syncState = "synced"; item.session = try related(WorkoutSession.self, string: data["session_id"])
        item.exercise = try related(Exercise.self, string: data["exercise_id"]); item.position = Int32(number(data["position"])); item.snapshotExerciseName = data["name"] as? String
        item.snapshotTrackingType = data["tracking_type"] as? String; item.snapshotDifficultyType = data["difficulty_type"] as? String
        item.snapshotPrimaryMuscleName = data["primary_muscle_name"] as? String; item.snapshotPrimaryMuscleColorHex = data["primary_muscle_color"] as? String
        item.snapshotTargetRestSeconds = NSNumber(value: number(data["target_rest_seconds"]))
    }
    private func applySessionSet(_ uuid: UUID, _ data: [String: Any]) throws {
        let item = try object(SessionSet.self, uuid: uuid); item.clientUUID = uuid; item.syncState = "synced"; item.sessionExercise = try related(SessionExercise.self, string: data["session_exercise_id"])
        item.setNumber = Int32(number(data["number"])); item.completed = data["completed"] as? Bool ?? false; item.completedAt = date(data["completed_at"]); item.isWarmup = data["warmup"] as? Bool ?? false
        item.reps = Int32(number(data["reps"])); item.timeSeconds = double(data["time_seconds"]); item.distance = decimalNumber(data["distance"]); item.weight = decimalNumber(data["weight"]); item.pace = double(data["pace"])
    }

    private func object<T: NSManagedObject>(_ type: T.Type, uuid: UUID) throws -> T {
        if let value = try existing(type, uuid: uuid) { return value }
        return T(context: context)
    }
    private func existing<T: NSManagedObject>(_ type: T.Type, uuid: UUID) throws -> T? {
        let request = NSFetchRequest<T>(entityName: String(describing: type)); request.fetchLimit = 1; request.predicate = NSPredicate(format: "clientUUID == %@", uuid as CVarArg); return try context.fetch(request).first
    }
    private func existing<T: NSManagedObject>(_ type: T.Type, serverUUID: UUID) throws -> T? {
        let request = NSFetchRequest<T>(entityName: String(describing: type)); request.fetchLimit = 1; request.predicate = NSPredicate(format: "serverID == %@", serverUUID as CVarArg); return try context.fetch(request).first
    }
    private func muscle(named name: String, color: String) throws -> Muscle {
        let request = Muscle.fetchRequest(); request.fetchLimit = 1; request.predicate = NSPredicate(format: "name =[c] %@", name)
        if let muscle = try context.fetch(request).first { return muscle }
        let muscle = Muscle(context: context); muscle.serverID = UUID(); muscle.name = name; muscle.colorHex = color; return muscle
    }
    private func related<T: NSManagedObject>(_ type: T.Type, string: Any?) throws -> T? { guard let raw = string as? String, let uuid = UUID(uuidString: raw) else { return nil }; return try existing(type, uuid: uuid) }
    private func deleteRemote(entity: String, uuid: UUID) {
        let names = ["exercise": "Exercise", "tag": "Tag", "workout": "WorkoutTemplate", "template_exercise": "TemplateExercise", "template_set": "TemplatePlannedSet"]
        guard let name = names[entity] else { return }; let request = NSFetchRequest<NSManagedObject>(entityName: name); request.predicate = NSPredicate(format: "clientUUID == %@", uuid as CVarArg); (try? context.fetch(request))?.forEach(context.delete)
    }
    private func hasPendingLocal(entity: String, uuid: UUID) -> Bool {
        let names = ["exercise": "Exercise", "tag": "Tag", "workout": "WorkoutTemplate", "template_exercise": "TemplateExercise", "template_set": "TemplatePlannedSet", "workout_session": "WorkoutSession", "session_exercise": "SessionExercise", "session_set": "SessionSet"]
        guard let name = names[entity] else { return false }; let request = NSFetchRequest<NSManagedObject>(entityName: name); request.fetchLimit = 1; request.predicate = NSPredicate(format: "clientUUID == %@ AND syncState != %@", uuid as CVarArg, "synced"); return ((try? context.count(for: request)) ?? 0) > 0
    }
    private func date(_ value: Any?) -> Date? { guard let string = value as? String else { return nil }; return ISO8601DateFormatter().date(from: string) }
    private func number(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? Int(value as? String ?? "") ?? 0 }
    private func double(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? Double(value as? String ?? "") ?? 0 }
    private func decimalNumber(_ value: Any?) -> NSDecimalNumber? { guard !(value is NSNull), let value else { return nil }; return NSDecimalNumber(string: String(describing: value)) }
    private func id(_ client: UUID?, _ server: UUID?) -> String { (client ?? server)?.uuidString ?? "" }
    private func iso(_ date: Date?) -> String { ISO8601DateFormatter().string(from: date ?? .distantPast) }
    private func decimal(_ number: NSDecimalNumber?) -> Any { number?.stringValue ?? NSNull() }
    private func value<T>(_ value: T?) -> Any { value ?? NSNull() }
}
