import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct TimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var deadline: Date
    }
    var key: String
    var title: String
}
