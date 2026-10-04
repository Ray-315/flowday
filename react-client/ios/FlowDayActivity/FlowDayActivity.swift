import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FlowDayActivityBundle: WidgetBundle {
    var body: some Widget { FlowDayActivity() }
}
struct FlowDayActivity: Widget {
    private let accent = Color(red: 0.38, green: 0.46, blue: 0.95)
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlowActivityAttributes.self) { context in
            HStack(spacing: 16) {
                Image(systemName: "timer").font(.title2).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text("FlowDay · 专注进行中").font(.caption).foregroundStyle(.secondary)
                    Text(context.state.title).font(.headline).lineLimit(2)
                }
                Spacer(minLength: 8)
                countdown(context).font(.title2.monospacedDigit()).frame(maxWidth: 100)
            }
            .padding(20)
            .activityBackgroundTint(Color(.secondarySystemBackground))
            .activitySystemActionForegroundColor(accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("FlowDay", systemImage: "timer").foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context).monospacedDigit().frame(maxWidth: 100)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(context.state.title).font(.headline).lineLimit(2)
                        ProgressView(timerInterval: context.state.start...context.state.end, countsDown: false)
                            .tint(accent).labelsHidden()
                        Text(context.isStale ? "时间已到，打开 FlowDay 结束" : "点按返回 FlowDay")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(accent)
            } compactTrailing: {
                countdown(context).monospacedDigit().frame(width: 56)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(accent)
            }
            .keylineTint(accent)
        }
    }
    @ViewBuilder private func countdown(_ context: ActivityViewContext<FlowActivityAttributes>) -> some View {
        if context.isStale { Text("已到时") }
        else { Text(timerInterval: context.state.start...context.state.end, countsDown: true) }
    }
}
