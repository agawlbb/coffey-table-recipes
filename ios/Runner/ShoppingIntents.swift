import AppIntents
import FirebaseCore
import FirebaseAuth
import Foundation

// Uses the same Firebase identity and WebSocket protocol as the foreground app.
// No iCloud credentials or separate household tokens are created.
@MainActor
final class SiriConnection {
    let user: User
    let session: URLSession
    let socket: URLSessionWebSocketTask
    let deadline: Task<Void, Never>
    private var sequence = 0

    static func failure(_ message: String) -> NSError {
        NSError(domain: "CTRSiri", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func firebaseOptions(info: [String: Any]) throws -> FirebaseOptions {
        guard let settings = info["CTRFirebaseOptions"] as? [String: String],
              let appID = settings["FIREBASE_IOS_APP_ID"], !appID.isEmpty,
              let apiKey = settings["FIREBASE_IOS_API_KEY"], !apiKey.isEmpty,
              let sender = settings["FIREBASE_SENDER_ID"], !sender.isEmpty,
              let project = settings["FIREBASE_PROJECT_ID"], !project.isEmpty,
              let client = settings["GOOGLE_IOS_CLIENT_ID"], !client.isEmpty else {
            throw failure("CTR’s Siri configuration is missing. Install the latest app update.")
        }
        let options = FirebaseOptions(googleAppID: appID, gcmSenderID: sender)
        options.apiKey = apiKey
        options.projectID = project
        options.clientID = client
        options.bundleID = Bundle.main.bundleIdentifier
        return options
    }

    static func open() async throws -> SiriConnection {
        if FirebaseApp.app() == nil {
            let options = try firebaseOptions(info: Bundle.main.infoDictionary ?? [:])
            FirebaseApp.configure(options: options)
        }
        let auth = Auth.auth()
        // currentUser can be nil while Firebase is restoring its Keychain state.
        let user: User? = await withCheckedContinuation { continuation in
            var handle: AuthStateDidChangeListenerHandle?
            var resolved = false
            handle = auth.addStateDidChangeListener { _, user in
                guard !resolved else { return }
                resolved = true
                if let handle { auth.removeStateDidChangeListener(handle) }
                continuation.resume(returning: user)
            }
        }
        try Task.checkCancellation()
        guard let user else { throw failure("Open CTR and sign in before using Siri.") }
        return SiriConnection(user: user)
    }

    static func errorMessage(_ error: Error, adding: Bool = false) -> String {
        let failure = error as NSError
        let message = failure.domain == "CTRSiri" ? failure.localizedDescription
            : "I couldn’t reach CTR. Open the app to check your connection and sign-in."
        return adding ? message + " Check your shopping list before trying again." : message
    }

    private init(user: User) {
        self.user = user
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 25
        session = URLSession(configuration: config)
        socket = session.webSocketTask(with: URL(string: "wss://coffeybean.com/ctr/shopping")!)
        let connection = socket
        deadline = Task {
            do { try await Task.sleep(nanoseconds: 25_000_000_000) }
            catch { return }
            connection.cancel(with: .goingAway, reason: nil)
        }
        socket.resume()
    }

    func close() {
        deadline.cancel()
        socket.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }

    func checkAccount() throws {
        guard Auth.auth().currentUser?.uid == user.uid else {
            throw Self.failure("Your account changed. Please try again.")
        }
    }

    func send(_ value: [String: Any]) async throws {
        try checkAccount()
        try await socket.send(.data(JSONSerialization.data(withJSONObject: value)))
    }

    func receive() async throws -> [String: Any] {
        let message = try await socket.receive()
        try checkAccount()
        let data: Data
        switch message {
        case .data(let value): data = value
        case .string(let value): data = Data(value.utf8)
        @unknown default: throw Self.failure("CTR returned an unreadable response.")
        }
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Self.failure("CTR returned an unreadable response.")
        }
        if value["type"] as? String == "error" {
            throw Self.failure("CTR could not complete the request. Open the app to check your connection and access.")
        }
        return value
    }

    func authenticate(scope: String = "app") async throws -> [String: Any] {
        let token: String = try await withCheckedThrowingContinuation { continuation in
            user.getIDTokenForcingRefresh(false) { token, error in
                if let token { continuation.resume(returning: token) }
                else { continuation.resume(throwing: error ?? Self.failure("Open CTR and sign in again.")) }
            }
        }
        try await send(["v": 1, "type": "auth", "scope": scope, "household_id": NSNull(), "token": token])
        let ready = try await receive()
        guard ready["type"] as? String == "ready", let data = ready["data"] as? [String: Any] else {
            throw Self.failure("CTR did not confirm your connection. Please try again.")
        }
        return data
    }

    func request(_ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        sequence += 1
        let id = "siri-\(sequence)"
        var request: [String: Any] = ["v": 1, "type": "request", "id": id, "path": path]
        if let body { request["body"] = body }
        try await send(request)
        while true {
            let response = try await receive()
            if response["type"] as? String == "snapshot" { continue }
            guard response["id"] as? String == id, response["type"] as? String == "response",
                  let data = response["data"] as? [String: Any] else {
                throw Self.failure("CTR did not confirm the request. Check the app before trying again.")
            }
            return data
        }
    }

    static func households(_ snapshot: [String: Any]) throws -> [(id: String, label: String)] {
        guard let account = snapshot["account"] as? [String: Any],
              let rows = account["households"] as? [[String: Any]], !rows.isEmpty else {
            throw failure("Open CTR and join or choose a household first.")
        }
        return try rows.map { row in
            guard let id = row["id"] as? String, let name = row["name"] as? String else {
                throw failure("CTR returned unreadable household details.")
            }
            let duplicates = rows.filter { $0["name"] as? String == name }.count > 1
            return (id, duplicates ? "\(name) (\(id))" : name)
        }
    }
}

@available(iOS 16.0, *)
struct AddCTRShoppingItem: AppIntent {
    static var title: LocalizedStringResource = "Add to my CTR list"
    static var description = IntentDescription("Add an item to your household shopping list.")
    static var openAppWhenRun = false
    @Parameter(title: "Item", requestValueDialog: "What would you like to add?")
    var item: String
    @Parameter(title: "Household") var household: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let name = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 200 else {
            throw $item.needsValueError("What would you like to add? Use up to 200 characters.")
        }
        // Obtain household choices before any write. Do not keep a socket open
        // while Siri waits for the user to choose a household.
        let choices: [(id: String, label: String)]
        do { choices = try await CTRSiriHouseholds.load() }
        catch { return .result(dialog: "\(SiriConnection.errorMessage(error))") }
        let selected = try await CTRSiriHouseholds.select(choices, value: household) {
            try await $household.requestDisambiguation(among: $0, dialog: "Which household?")
        }
        do {
            let connection = try await SiriConnection.open()
            defer { connection.close() }
            let snapshot = try await connection.authenticate()
            let account = snapshot["account"] as? [String: Any]
            let user = account?["user"] as? [String: Any]
            guard user?["child_mode"] as? Bool == false else {
                throw SiriConnection.failure("Child mode allows viewing only. Open CTR to change it.")
            }
            let id = UUID().uuidString.lowercased()
            let path = "/households/\(selected)/shopping-list"
            _ = try await connection.request(path, body: [
                "upsert_items": [["id": id, "name": name, "department": "", "checked": false]],
                "client_change_id": UUID().uuidString.lowercased()
            ])
            let readback = try await connection.request(path)
            guard let items = readback["items"] as? [[String: Any]],
                  items.contains(where: { $0["id"] as? String == id && $0["name"] as? String == name }) else {
                throw SiriConnection.failure("CTR did not confirm the addition.")
            }
            return .result(dialog: "Added \(name) to your shopping list.")
        } catch {
            return .result(dialog: "\(SiriConnection.errorMessage(error, adding: true))")
        }
    }
}

@available(iOS 16.0, *)
@MainActor
enum CTRSiriHouseholds {
    static func load() async throws -> [(id: String, label: String)] {
        let connection = try await SiriConnection.open()
        defer { connection.close() }
        _ = try await connection.authenticate(scope: "account")
        let account = try await connection.request("/me")
        return try SiriConnection.households(["account": account])
    }

    static func select(_ choices: [(id: String, label: String)], value: String?,
                       ask: ([String]) async throws -> String) async throws -> String {
        if let value, let match = choices.first(where: { $0.label == value }) { return match.id }
        if value != nil { throw SiriConnection.failure("That household is unavailable. Please choose it again in CTR.") }
        if choices.count == 1 { return choices[0].id }
        let label = try await ask(choices.map(\.label))
        guard let match = choices.first(where: { $0.label == label }) else {
            throw SiriConnection.failure("Please choose a household in CTR.")
        }
        return match.id
    }
}

@available(iOS 16.0, *)
enum CTRDinnerDay: String, AppEnum {
    case today, tomorrow
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Dinner date"
    static var caseDisplayRepresentations: [CTRDinnerDay: DisplayRepresentation] = [
        .today: "Tonight", .tomorrow: "Tomorrow night"
    ]
}

@available(iOS 16.0, *)
struct CTRDinner: AppIntent {
    static var title: LocalizedStringResource = "What's for dinner?"
    static var description = IntentDescription("Read your household's planned dinner.")
    static var openAppWhenRun = false
    @Parameter(title: "Day", default: .today) var day: CTRDinnerDay
    @Parameter(title: "Household") var household: String?

    init() {}
    init(day: CTRDinnerDay) { self.day = day }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let choices: [(id: String, label: String)]
        do { choices = try await CTRSiriHouseholds.load() }
        catch { return .result(dialog: "\(SiriConnection.errorMessage(error))") }
        let selected = try await CTRSiriHouseholds.select(choices, value: household) {
            try await $household.requestDisambiguation(among: $0, dialog: "Which household?")
        }
        do {
            let connection = try await SiriConnection.open()
            defer { connection.close() }
            _ = try await connection.authenticate()
            let plan = try await connection.request("/households/\(selected)/meal-plan?from=2000-01-01&to=2199-12-31")
            let text = try CTRDinnerResponse.text(plan: plan, tomorrow: day == .tomorrow)
            return .result(dialog: "\(text)")
        } catch {
            return .result(dialog: "\(SiriConnection.errorMessage(error))")
        }
    }
}

@available(iOS 16.0, *)
struct CTRShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddCTRShoppingItem(), phrases: [
            "Add to my \(.applicationName) list"
        ], shortTitle: "Add shopping item", systemImageName: "cart.badge.plus")
        AppShortcut(intent: CTRDinner(day: .today), phrases: [
            "Ask \(.applicationName) what's for dinner",
            "Ask \(.applicationName) what's for dinner tonight"
        ], shortTitle: "Dinner tonight", systemImageName: "fork.knife")
        AppShortcut(intent: CTRDinner(day: .tomorrow), phrases: [
            "Ask \(.applicationName) what's for dinner tomorrow",
            "Ask \(.applicationName) what's for dinner tomorrow night"
        ], shortTitle: "Dinner tomorrow", systemImageName: "fork.knife")
    }
}
