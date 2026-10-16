import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RecipeTimerWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Label(context.attributes.title, systemImage: "timer")
                Text(timerInterval: Date.distantPast...context.state.deadline, countsDown: true).font(.title.monospacedDigit())
                Text("Open the app to edit or cancel").font(.caption)
            }.padding().activityBackgroundTint(Color(red: 0.96, green: 0.93, blue: 0.87))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "timer") }
                DynamicIslandExpandedRegion(.bottom) { Text(context.attributes.title) }
                DynamicIslandExpandedRegion(.trailing) { Text(timerInterval: Date.distantPast...context.state.deadline, countsDown: true).monospacedDigit() }
            } compactLeading: { Image(systemName: "timer") }
            compactTrailing: { Text(timerInterval: Date.distantPast...context.state.deadline, countsDown: true).monospacedDigit().frame(width: 50) }
            minimal: { Image(systemName: "timer") }
        }
    }
}
