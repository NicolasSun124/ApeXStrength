import ActivityKit
import SwiftUI
import WidgetKit

struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let endDate: Date
    }

    let workoutName: String
}

@main
struct RestTimerWidgetBundle: WidgetBundle {
    var body: some Widget {
        RestTimerLiveActivity()
    }
}

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "hourglass")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest Timer")
                        .font(.headline)
                    Text(context.attributes.workoutName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                countdown(until: context.state.endDate)
                    .font(.title2.bold().monospacedDigit())
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.9))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Rest", systemImage: "hourglass")
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(until: context.state.endDate)
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.workoutName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "hourglass")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                countdown(until: context.state.endDate)
                    .font(.caption2.monospacedDigit())
                    .frame(width: 42)
            } minimal: {
                Image(systemName: "hourglass")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func countdown(until endDate: Date) -> Text {
        Text(timerInterval: Date()...max(endDate, Date()), countsDown: true)
    }
}
