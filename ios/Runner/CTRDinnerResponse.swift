import Foundation

// Meal plans currently group dishes by date, without breakfast/lunch/dinner slots.
// Use the server's household-local date, never the phone's date or cached meals.
enum CTRDinnerResponse {
    static func text(plan: [String: Any], tomorrow: Bool) throws -> String {
        let invalid = NSError(domain: "CTRSiri", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "CTR could not read your meal plan. Please try again."
        ])
        guard let today = plan["today"] as? String,
              let entries = plan["entries"] as? [[String: Any]] else { throw invalid }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let start = formatter.date(from: today), formatter.string(from: start) == today else { throw invalid }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(byAdding: .day, value: tomorrow ? 1 : 0, to: start) else { throw invalid }
        let target = formatter.string(from: date)
        let titles = try entries.filter { $0["plan_date"] as? String == target }.map { row -> String in
            guard let title = row["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw invalid }
            return title
        }
        let when = tomorrow ? "tomorrow night" : "tonight"
        if titles.isEmpty { return "Nothing is planned for dinner \(when)." }
        let dishes: String
        if titles.count == 1 { dishes = titles[0] }
        else { dishes = titles.dropLast().joined(separator: ", ") + " and " + titles.last! }
        return "For dinner \(when): \(dishes)."
    }
}
