import Flutter
import UIKit
import UserNotifications
import ActivityKit
import AlarmKit
import SwiftUI
import AVFoundation

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
        channel.setMethodCallHandler { call, result in
            Task { @MainActor in
                do {
                    let args = call.arguments as? [String: Any] ?? [:]
                    switch call.method {
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
                            for (key, row) in saved where row["mode"] as? String == "alarmkit" && !ids.contains(row["id"] as? String ?? "") {
                                saved.removeValue(forKey: key); await endActivity(key)
                            }
                            rows = saved
                        }
                        result(saved.map { ["key": $0.key, "deadline": $0.value["deadline"] ?? 0, "title": $0.value["title"] ?? "Cooking timer"] })
                    case "cancel":
                        guard let key = args["key"] as? String else { throw failure("Missing timer.") }
                        try await cancel(key); result(nil)
                    case "schedule":
                        guard let key = args["key"] as? String, let deadline = args["deadline"] as? NSNumber, let title = args["title"] as? String else { throw failure("Missing timer details.") }
                        try await schedule(key, deadline.doubleValue, title); result(nil)
                    default: result(FlutterMethodNotImplemented)
                    }
                } catch { result(FlutterError(code: "timer", message: error.localizedDescription, details: nil)) }
            }
        }
    }
    static func failure(_ text: String) -> NSError { NSError(domain: "RecipeTimer", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    static func schedule(_ key: String, _ milliseconds: Double, _ title: String) async throws {
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
            let presentation = AlarmPresentation(alert: .init(title: LocalizedStringResource(stringLiteral: title), stopButton: stop))
            let attributes = AlarmAttributes(presentation: presentation, metadata: RecipeAlarmMetadata(), tintColor: Color.green)
            let configuration = AlarmManager.AlarmConfiguration.alarm(schedule: .fixed(date), attributes: attributes, sound: .named(tone.isEmpty ? "default.wav" : tone))
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            mode = "alarmkit"
        } else {
            let center = UNUserNotificationCenter.current()
            guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else { throw failure("Allow notifications in Settings to start a cooking timer.") }
            let pending = await center.pendingNotificationRequests()
            guard pending.count < 60 else { throw failure("Too many pending timers. Cancel a timer first.") }
            let content = UNMutableNotificationContent()
            content.title = title; content.body = "Time is up"; content.userInfo = ["recipeTimer": true]
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
        saved[key] = ["id": id.uuidString, "deadline": milliseconds, "title": title, "mode": mode]
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
