import Flutter
import UIKit
import UserNotifications
import ActivityKit
import AlarmKit
import SwiftUI
import AVFoundation
import AppIntents
import FirebaseCore
import FirebaseAuth

@available(iOS 26.0, *)
struct RecipeAlarmMetadata: AlarmMetadata {}

@MainActor
enum RecipeTimers {
    static var previewPlayer: AVAudioPlayer?
    static var previewStop: DispatchWorkItem?
    static var previewObserver: NSObjectProtocol?
    static func stopPreview() {
        previewStop?.cancel(); previewStop = nil
        guard previewPlayer != nil else { return }
        previewPlayer?.stop(); previewPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    static func previewTone(_ tone: String) throws {
        stopPreview()
        guard ["", "gentle.wav", "bright.wav"].contains(tone),
              let url = Bundle.main.url(forResource: tone.isEmpty ? "default" : String(tone.dropLast(4)), withExtension: "wav") else { throw failure("This sound is unavailable.") }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: .mixWithOthers)
        try session.setActive(true)
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            previewPlayer = player
            guard player.play() else { throw failure("Could not play this sound.") }
            let stop = DispatchWorkItem { Task { @MainActor in
                if previewPlayer === player { stopPreview() }
            } }
            previewStop = stop
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: stop)
        } catch { stopPreview(); try? session.setActive(false); throw error }
    }
    static var syncChannel: FlutterMethodChannel?
    static var syncTail: Task<Void, Never>?
    static func serializedSync(_ action: @escaping @MainActor () async throws -> Void) async throws {
        let previous = syncTail
        let operation = Task { @MainActor in
            await previous?.value
            try await action()
        }
        syncTail = Task { _ = try? await operation.value }
        try await operation.value
    }
    static let defaults = UserDefaults.standard
    static var rows: [String: [String: Any]] {
        get { defaults.dictionary(forKey: "recipeTimers") as? [String: [String: Any]] ?? [:] }
        set { defaults.set(newValue, forKey: "recipeTimers") }
    }
    static func register(_ messenger: FlutterBinaryMessenger) {
        if let observer = previewObserver { NotificationCenter.default.removeObserver(observer) }
        previewObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in stopPreview() }
        }
        let channel = FlutterMethodChannel(name: "coffey_table_recipes/timers", binaryMessenger: messenger)
        syncChannel = channel
        channel.setMethodCallHandler { call, result in
            Task { @MainActor in
                do {
                    let args = call.arguments as? [String: Any] ?? [:]
                    switch call.method {
                    case "configureSync":
                        try await serializedSync { try await configureSync(args) }; result(nil)
                    case "pendingActions": result(pendingActions)
                    case "acknowledgeAction": acknowledgeAction(args["account_uid"] as? String ?? "", args["operation_id"] as? String ?? ""); result(nil)
                    case "syncActions": Task { await syncActions() }; result(nil)
                    case "syncRevision":
                        result((defaults.dictionary(forKey: "timerSyncRevisions")?[args["timer_id"] as? String ?? ""] as? NSNumber)?.int64Value ?? 0)
                    case "recordSyncRevision", "forgetSyncRevision":
                        try await serializedSync {
                            if let id = args["timer_id"] as? String {
                                var versions = defaults.dictionary(forKey: "timerSyncRevisions") ?? [:]
                                if call.method == "forgetSyncRevision" { versions.removeValue(forKey: id) }
                                else if let version = args["revision"] as? NSNumber, version.int64Value > ((versions[id] as? NSNumber)?.int64Value ?? 0) { versions[id] = version }
                                defaults.set(versions, forKey: "timerSyncRevisions")
                            }
                        }
                        result(nil)
                    case "applyRemote":
                        try await serializedSync { try await applyRemote(args) }; result(nil)
                    case "requestTimerPermissions":
                        let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                        guard allowed else { throw failure("Allow notifications in Settings, then try again.") }
                        if #available(iOS 26.0, *) {
                            guard try await AlarmManager.shared.requestAuthorization() == .authorized else { throw failure("Allow alarms in Settings, then try again.") }
                        }
                        result(nil)
                    case "settings":
                        let mode: String
                        if #available(iOS 26.0, *) { mode = "AlarmKit alarms require permission. Live Activities are optional and can be disabled by the system. Device shutdown and force-stop behavior are not guaranteed." }
                        else { mode = "On iOS before 26, timers use notification sounds, not persistent alarms. Silent mode, Focus and notification settings can suppress sound. Live Activities require iOS 16.2 or later." }
                        result(["tone": defaults.string(forKey: "recipeTimerTone") ?? "", "mode": mode])
                    case "setTone":
                        guard let tone = args["tone"] as? String, ["", "gentle.wav", "bright.wav"].contains(tone) else { throw failure("Choose a timer tone.") }
                        defaults.set(tone, forKey: "recipeTimerTone"); result(nil)
                    case "previewTone":
                        try previewTone(args["tone"] as? String ?? ""); result(nil)
                    case "stopPreview":
                        stopPreview(); result(nil)
                    case "list":
                        var saved = rows
                        if #available(iOS 26.0, *) {
                            let ids = Set(try AlarmManager.shared.alarms.map { $0.id.uuidString })
                            for (key, row) in saved where row["mode"] as? String == "alarmkit" && !ids.contains(row["id"] as? String ?? "") && ((row["extension_seconds"] as? NSNumber)?.intValue ?? 0) <= 0 && row["native_actions"] as? Bool != true {
                                saved.removeValue(forKey: key); await endActivity(key)
                            }
                            rows = saved
                        }
                        result(saved.map { ["key": $0.key, "deadline": $0.value["deadline"] ?? 0, "title": $0.value["title"] ?? "Cooking timer", "extension_seconds": $0.value["extension_seconds"] ?? 0] })
                    case "cancel":
                        guard let key = args["key"] as? String else { throw failure("Missing timer.") }
                        try await serializedSync { try await cancel(key) }; result(nil)
                    case "schedule":
                        guard let key = args["key"] as? String, let deadline = args["deadline"] as? NSNumber, let title = args["title"] as? String else { throw failure("Missing timer details.") }
                        try await serializedSync { try await schedule(key, deadline.doubleValue, title, (args["extension_seconds"] as? NSNumber)?.intValue ?? 0) }; result(nil)
                    default: result(FlutterMethodNotImplemented)
                    }
                } catch { result(FlutterError(code: "timer", message: error.localizedDescription, details: nil)) }
            }
        }
    }
    static func failure(_ text: String) -> NSError { NSError(domain: "RecipeTimer", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    static func schedule(_ key: String, _ milliseconds: Double, _ title: String, _ extensionSeconds: Int = 0) async throws {
        let date = Date(timeIntervalSince1970: milliseconds / 1000)
        guard date > Date() else { throw failure("Choose a future timer deadline.") }
        let old = rows[key]
        // Schedule a new ID first: if permission or scheduling fails, the old timer survives.
        let id = UUID()
        let tone = defaults.string(forKey: "recipeTimerTone") ?? ""
        var mode = "notification"
        if #available(iOS 26.0, *) {
            guard try await AlarmManager.shared.requestAuthorization() == .authorized else { throw failure("Allow alarms in Settings to start a cooking timer.") }
            let stop = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle")
            let add = extensionSeconds > 0 ? AlarmButton(text: LocalizedStringResource(stringLiteral: extensionLabel(extensionSeconds)), textColor: .white, systemImageName: "timer") : nil
            let presentation = AlarmPresentation(alert: .init(title: LocalizedStringResource(stringLiteral: title), stopButton: stop, secondaryButton: add, secondaryButtonBehavior: extensionSeconds > 0 ? .custom : nil))
            let attributes = AlarmAttributes(presentation: presentation, metadata: RecipeAlarmMetadata(), tintColor: Color.green)
            let configuration = AlarmManager.AlarmConfiguration.alarm(schedule: .fixed(date), attributes: attributes, stopIntent: RecipeTimerActionIntent(key: key, alarmID: id.uuidString, extend: false), secondaryIntent: extensionSeconds > 0 ? RecipeTimerActionIntent(key: key, alarmID: id.uuidString, extend: true) : nil, sound: .named(tone.isEmpty ? "default.wav" : tone))
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            mode = "alarmkit"
        } else {
            let center = UNUserNotificationCenter.current()
            guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else { throw failure("Allow notifications in Settings to start a cooking timer.") }
            let pending = await center.pendingNotificationRequests()
            guard pending.count < 60 else { throw failure("Too many pending timers. Cancel a timer first.") }
            let content = UNMutableNotificationContent()
            content.title = title; content.body = "Time is up"; content.userInfo = ["recipeTimer": true]
            var actions = [UNNotificationAction(identifier: "timer_stop", title: "Stop", options: [])]
            if extensionSeconds > 0 { actions.append(UNNotificationAction(identifier: "timer_extend", title: extensionLabel(extensionSeconds), options: [])) }
            let category = UNNotificationCategory(identifier: "cooking-timer-\(extensionSeconds)", actions: actions, intentIdentifiers: [], options: [])
            var categories = await center.notificationCategories(); categories.insert(category); center.setNotificationCategories(categories)
            content.categoryIdentifier = category.identifier
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: tone.isEmpty ? "default.wav" : tone))
            let request = UNNotificationRequest(identifier: id.uuidString, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false))
            try await center.add(request)
        }
        if let old {
            do { try cancelNative(old) }
            catch {
                try? cancelNative(["id": id.uuidString, "mode": mode])
                throw error
            }
        }
        var saved = rows
        saved[key] = ["id": id.uuidString, "deadline": milliseconds, "title": title, "mode": mode, "extension_seconds": extensionSeconds, "native_actions": true]
        rows = saved
        await endActivity(key)
        if #available(iOS 16.2, *), ActivityAuthorizationInfo().areActivitiesEnabled {
            // A missing/disabled Live Activity never cancels the independently scheduled alarm.
            _ = try? Activity<TimerActivityAttributes>.request(attributes: .init(key: key, title: title), content: ActivityContent(state: .init(deadline: date), staleDate: date), pushType: nil)
        }
    }
    static func cancelNative(_ row: [String: Any]) throws {
        guard let raw = row["id"] as? String, let id = UUID(uuidString: raw) else { return }
        if #available(iOS 26.0, *), row["mode"] as? String == "alarmkit" { if try AlarmManager.shared.alarms.contains(where: { $0.id == id }) { try AlarmManager.shared.cancel(id: id) } }
        else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [raw])
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [raw])
        }
    }
    static func cancel(_ key: String) async throws {
        if let row = rows[key] { try cancelNative(row) }
        var saved = rows; saved.removeValue(forKey: key); rows = saved
        await endActivity(key)
    }
    static func endActivity(_ key: String) async {
        if #available(iOS 16.2, *) {
            for activity in Activity<TimerActivityAttributes>.activities where activity.attributes.key == key {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}


@MainActor
extension RecipeTimers {
    static func configureSync(_ args: [String: Any]) async throws {
        let uid = args["account_uid"] as? String ?? ""
        let enabled = args["receive_timers"] as? Bool ?? false
        let previous = defaults.string(forKey: "timerSyncUid") ?? ""
        pendingActions = pendingActions.filter { $0["account_uid"] as? String == uid }
        if args["guard_only"] as? Bool == true && previous == uid { return }
        var versions = defaults.dictionary(forKey: "timerSyncRevisions") ?? [:]
        // Reject pushes immediately; cancellation can then safely await AlarmKit.
        defaults.set(false, forKey: "timerSyncReceive")
        defaults.set(uid, forKey: "timerSyncUid")
        let sessions = args["session_ids"] as? [String] ?? (previous == uid ? defaults.stringArray(forKey: "cookingSessions") ?? [] : [])
        for key in rows.keys where key.hasPrefix("remote:session:") {
            let parts = key.components(separatedBy: ":")
            if parts.count > 2 && !sessions.contains(parts[2]) { try await cancel(key) }
        }
        defaults.set(sessions, forKey: "cookingSessions")
        if let offset = args["clock_offset_ms"] as? NSNumber { defaults.set(offset, forKey: "cookingClockOffset") }
        if previous != uid || !enabled {
            for key in rows.keys {
                if (key.hasPrefix("remote:") && !key.hasPrefix("remote:session:")) || (previous != uid && !previous.isEmpty) {
                    try await cancel(key)
                    if key.hasPrefix("remote:") { versions.removeValue(forKey: String(key.dropFirst(7))) }
                }
            }
        }
        defaults.set(previous != uid ? [:] : versions, forKey: "timerSyncRevisions")
        defaults.set(args["installation_id"] as? String ?? "", forKey: "timerSyncInstallation")
        defaults.set(enabled, forKey: "timerSyncReceive")
    }

    static func applyRemote(_ data: [String: Any]) async throws {
        let uid = defaults.string(forKey: "timerSyncUid") ?? ""
        let installation = defaults.string(forKey: "timerSyncInstallation") ?? ""
        guard !uid.isEmpty, data["account_uid"] as? String == uid,
              data["target_device"] as? String == installation else { return }
        guard let id = data["timer_id"] as? String,
              id.range(of: "^[A-Za-z0-9:_-]{1,160}$", options: .regularExpression) != nil,
              let version = Int64(String(describing: data["revision"] ?? "")),
              let serverDeadline = Double(String(describing: data["deadline_ms"] ?? "")) else { throw failure("Invalid shared timer.") }
        guard id.hasPrefix("session:") else { return }
        let deadline = serverDeadline - defaults.double(forKey: "cookingClockOffset")
        let parts = id.components(separatedBy: ":")
        guard parts.count > 1, (defaults.stringArray(forKey: "cookingSessions") ?? []).contains(parts[1]) else { return }
        var versions = defaults.dictionary(forKey: "timerSyncRevisions") ?? [:]
        let current = (versions[id] as? NSNumber)?.int64Value ?? 0
        guard version > current else { return }
        let key = "remote:" + id
        let cancelled = ["1", "true"].contains(String(describing: data["cancelled"] ?? ""))
        let extensionSeconds = Int(String(describing: data["extension_seconds"] ?? "0")) ?? 0
        if cancelled || (deadline <= Date().timeIntervalSince1970 * 1000 && extensionSeconds <= 0) {
            try await cancel(key)
        } else {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { throw failure("Allow notifications to receive this timer.") }
            if #available(iOS 26.0, *) {
                guard AlarmManager.shared.authorizationState == .authorized else { throw failure("Allow alarms to receive this timer.") }
            }
            let title = data["title"] as? String ?? "Cooking timer"
            let old = rows[key]
            if (old?["deadline"] as? NSNumber)?.doubleValue != deadline || old?["title"] as? String != title || ((old?["extension_seconds"] as? NSNumber)?.intValue ?? 0) != extensionSeconds {
                if deadline > Date().timeIntervalSince1970 * 1000 {
                    try await schedule(key, deadline, title, extensionSeconds)
                } else {
                    try await cancel(key)
                    var saved = rows
                    saved[key] = ["deadline": deadline, "title": title, "extension_seconds": extensionSeconds]
                    rows = saved
                }
            }
        }
        versions[id] = NSNumber(value: version)
        defaults.set(versions, forKey: "timerSyncRevisions")
        syncChannel?.invokeMethod("changed", arguments: nil)
    }

    static func receivePush(_ userInfo: [AnyHashable: Any], completion: @escaping (Bool) -> Void) {
        var data: [String: Any] = [:]
        for (key, value) in userInfo { if let key = key as? String { data[key] = value } }
        Task { @MainActor in
            do { try await serializedSync { try await applyRemote(data) }; completion(true) }
            catch { completion(false) } // Keep revision unchanged so opening the app retries.
        }
    }
}

@available(iOS 26.0, *)
struct RecipeTimerActionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Cooking timer"
    static var openAppWhenRun = false
    @Parameter(title: "Timer") var key: String
    @Parameter(title: "Alarm") var alarmID: String
    @Parameter(title: "Add remaining time") var extend: Bool
    init() { key = ""; alarmID = ""; extend = false }
    init(key: String, alarmID: String, extend: Bool) { self.key = key; self.alarmID = alarmID; self.extend = extend }
    func perform() async throws -> some IntentResult {
        try await RecipeTimers.serializedSync { try await RecipeTimers.notificationAction(key, alarmID, extend) }
        await RecipeTimers.syncActions()
        return .result()
    }
}

@MainActor
extension RecipeTimers {
    static var pendingActions: [[String: Any]] {
        get { defaults.array(forKey: "cookingTimerActions") as? [[String: Any]] ?? [] }
        set { defaults.set(newValue, forKey: "cookingTimerActions") }
    }
    static var sendingActions = false
    static func acknowledgeAction(_ uid: String, _ operation: String) {
        pendingActions = pendingActions.filter { ($0["account_uid"] as? String) != uid || ($0["operation_id"] as? String) != operation }
    }
    static func extensionLabel(_ seconds: Int) -> String {
        var parts: [String] = []
        if seconds / 3600 > 0 { parts.append("\(seconds / 3600) hr") }
        if seconds / 60 % 60 > 0 { parts.append("\(seconds / 60 % 60) min") }
        if seconds % 60 > 0 { parts.append("\(seconds % 60) sec") }
        return "Add " + parts.joined(separator: " ")
    }
    static func notificationAction(_ key: String, _ alarmID: String, _ extend: Bool) async throws {
        guard let row = rows[key], row["id"] as? String == alarmID else { return }
        let now = Date().timeIntervalSince1970 * 1000
        let oldDeadline = (row["deadline"] as? NSNumber)?.doubleValue ?? 0
        let extra = (row["extension_seconds"] as? NSNumber)?.intValue ?? 0
        guard !extend || (oldDeadline <= now && extra > 0) else { return }
        let deadline = extend ? now + Double(extra) * 1000 : oldDeadline
        if extend { try await schedule(key, deadline, row["title"] as? String ?? "Cooking timer", 0) }
        else { try await cancel(key) }
        if key.hasPrefix("remote:session:") {
            let parts = key.components(separatedBy: ":")
            let uid = defaults.string(forKey: "timerSyncUid") ?? ""
            if parts.count == 4 && !uid.isEmpty {
                let id = String(key.dropFirst(7))
                var revision = (defaults.dictionary(forKey: "timerSyncRevisions")?[id] as? NSNumber)?.int64Value ?? 0
                for action in pendingActions where action["session_id"] as? String == parts[2] {
                    if let body = action["body"] as? [String: Any], body["action_id"] as? String == parts[3] {
                        revision = max(revision, ((body["revision"] as? NSNumber)?.int64Value ?? 0) + 1)
                    }
                }
                var body: [String: Any] = ["action_id": parts[3], "cancelled": !extend, "extension_seconds": 0,
                    "deadline_ms": Int64(deadline + defaults.double(forKey: "cookingClockOffset")), "revision": revision, "expected_deadline_ms": Int64(oldDeadline + defaults.double(forKey: "cookingClockOffset"))]
                if extend { body["extend"] = true }
                pendingActions.append(["account_uid": uid, "installation_id": defaults.string(forKey: "timerSyncInstallation") ?? "",
                    "session_id": parts[2], "operation_id": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), "body": body])
            }
        }
        syncChannel?.invokeMethod("changed", arguments: nil)
    }
    static func handleNotification(_ response: UNNotificationResponse) async -> Bool {
        guard response.actionIdentifier == "timer_stop" || response.actionIdentifier == "timer_extend" else { return false }
        let alarmID = response.notification.request.identifier
        guard let key = rows.first(where: { $0.value["id"] as? String == alarmID })?.key else { return true }
        do {
            try await serializedSync { try await notificationAction(key, alarmID, response.actionIdentifier == "timer_extend") }
            await syncActions()
        } catch { /* Keep the unused extension available when scheduling fails. */ }
        return true
    }
    static func syncActions() async {
        guard !sendingActions else { return }
        sendingActions = true
        defer { sendingActions = false }
        // An intent can launch the process before Flutter finishes Firebase setup.
        for _ in 0..<10 {
            if FirebaseApp.app() != nil { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard FirebaseApp.app() != nil, let user = Auth.auth().currentUser else { return }
        while let action = pendingActions.first(where: { ($0["sent"] as? Bool) != true }) {
            guard action["account_uid"] as? String == user.uid, Auth.auth().currentUser?.uid == user.uid else { return }
            do {
                let token: String = try await withCheckedThrowingContinuation { continuation in
                    user.getIDTokenForcingRefresh(false) { token, error in
                        if let token { continuation.resume(returning: token) }
                        else { continuation.resume(throwing: error ?? failure("Sign in again.")) }
                    }
                }
                guard Auth.auth().currentUser?.uid == user.uid else { return }
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 8
                configuration.timeoutIntervalForResource = 8
                let session = URLSession(configuration: configuration)
                let socket = session.webSocketTask(with: URL(string: "wss://ctr.coffeybean.com/shopping")!)
                socket.resume()
                defer { socket.cancel(with: .normalClosure, reason: nil); session.invalidateAndCancel() }
                func send(_ value: [String: Any]) async throws {
                    try await socket.send(.data(JSONSerialization.data(withJSONObject: value)))
                }
                func receive() async throws -> [String: Any] {
                    let message = try await socket.receive()
                    let data: Data
                    switch message { case .data(let value): data = value; case .string(let value): data = Data(value.utf8); @unknown default: throw failure("Connection interrupted.") }
                    return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                }
                try await send(["v": 1, "type": "auth", "scope": "cooking", "household_id": NSNull(), "token": token])
                let ready = try await receive()
                guard ready["type"] as? String == "ready" else { return }
                var body = action["body"] as? [String: Any] ?? [:]
                body["installation_id"] = action["installation_id"]
                body["operation_id"] = action["operation_id"]
                try await send(["v": 1, "type": "request", "id": action["operation_id"] ?? "", "path": "/me/cooking-sessions/\(action["session_id"] as? String ?? "")/timer", "body": body])
                var response = try await receive()
                while response["type"] as? String == "snapshot" { response = try await receive() }
                guard Auth.auth().currentUser?.uid == user.uid else { return }
                if response["type"] as? String == "response" {
                    if let data = response["data"] as? [String: Any], let snapshot = data["session"] as? [String: Any], let timers = snapshot["timers"] as? [[String: Any]] {
                        for timer in timers where timer["action_id"] as? String == body["action_id"] as? String {
                            if let id = timer["timer_id"] as? String, let revision = timer["revision"] {
                                var versions = defaults.dictionary(forKey: "timerSyncRevisions") ?? [:]; versions[id] = revision; defaults.set(versions, forKey: "timerSyncRevisions")
                            }
                        }
                    }
                    pendingActions = pendingActions.map { row in
                        var copy = row
                        if row["operation_id"] as? String == action["operation_id"] as? String { copy["sent"] = true }
                        return copy
                    }
                } else if [404, 409, 422].contains(response["status"] as? Int ?? 0) {
                    acknowledgeAction(user.uid, action["operation_id"] as? String ?? "")
                } else { return }
                syncChannel?.invokeMethod("changed", arguments: nil)
            } catch { return } // Retain exact operation IDs for native or foreground retry.
        }
    }
}
