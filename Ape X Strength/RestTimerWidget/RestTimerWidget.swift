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
    private let backgroundColor = Color(red: 0.03, green: 0.04, blue: 0.15)
    private let accentColor = Color(red: 0.43, green: 0.92, blue: 0.94)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(backgroundColor)
                        .frame(width: 40, height: 40)
                        .background(accentColor, in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("REST TIMER")
                            .font(.caption.weight(.bold))
                            .tracking(1.1)
                            .foregroundStyle(accentColor)
                        Text(context.attributes.workoutName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("REMAINING")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.7))
                        countdown(until: context.state.endDate)
                            .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.75)
                    }
                }

                ProgressView(timerInterval: Date()...max(context.state.endDate, Date()), countsDown: true)
                    .tint(accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .activityBackgroundTint(backgroundColor)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Rest", systemImage: "hourglass")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(accentColor)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(until: context.state.endDate)
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.workoutName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        Text("Next set")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            } compactLeading: {
                Image(systemName: "hourglass")
                    .foregroundStyle(accentColor)
            } compactTrailing: {
                countdown(until: context.state.endDate)
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 46)
            } minimal: {
                Image(systemName: "hourglass")
                    .foregroundStyle(accentColor)
            }
            .keylineTint(accentColor)
        }
    }

    private func countdown(until endDate: Date) -> Text {
        Text(timerInterval: Date()...max(endDate, Date()), countsDown: true)
    }
}
