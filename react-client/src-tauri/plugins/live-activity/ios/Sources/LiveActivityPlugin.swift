import ActivityKit
import Foundation
import Tauri

private struct StartArgs: Decodable {
    let title: String
    let start: Double
    let end: Double
    let scope: String
    let eventId: String?
}

class LiveActivityPlugin: Plugin {
    // Serialize lifecycle changes: replacing an activity must not race with stopping it.
    private var operation: Task<Void, Never>?
    private func enqueue(_ body: @escaping @MainActor () async -> Void) {
        let previous = operation
        operation = Task { @MainActor in
            await previous?.value
            await body()
        }
    }
    @available(iOS 16.2, *)
    @MainActor private func snapshot() -> [String: Any] {
        let current = Activity<FlowActivityAttributes>.activities.first {
            ($0.activityState == .active || $0.activityState == .stale) && $0.content.state.end > Date()
        }
        var active: Any = NSNull()
        if let a = current {
            let state = a.content.state
            active = ["title": state.title, "start": state.start.timeIntervalSince1970 * 1000,
                      "end": state.end.timeIntervalSince1970 * 1000, "scope": a.attributes.scope,
                      "eventId": a.attributes.eventId as Any? ?? NSNull()]
        }
        return ["supported": true, "enabled": ActivityAuthorizationInfo().areActivitiesEnabled, "active": active]
    }
    @objc func status(_ invoke: Invoke) {
        enqueue {
            guard #available(iOS 16.2, *) else {
                invoke.resolve(["supported": false, "enabled": false, "active": NSNull()]); return
            }
            for activity in Activity<FlowActivityAttributes>.activities where activity.content.state.end <= Date() {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            invoke.resolve(self.snapshot())
        }
    }
    @objc func start(_ invoke: Invoke) {
        do {
            let args = try invoke.parseArgs(StartArgs.self)
            enqueue {
                guard #available(iOS 16.2, *) else { invoke.reject("实时活动需要 iOS 16.2 或更新版本"); return }
                guard ActivityAuthorizationInfo().areActivitiesEnabled else { invoke.reject("请在系统设置中允许 FlowDay 实时活动"); return }
                let now = Date(), start = Date(timeIntervalSince1970: args.start / 1000), end = Date(timeIntervalSince1970: args.end / 1000)
                guard !args.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      args.title.count <= 120, !args.scope.isEmpty,
                      start <= now.addingTimeInterval(5), end > now, end > start,
                      end.timeIntervalSince(now) <= 8 * 3600 else {
                    invoke.reject("请选择正在进行且在 8 小时内结束的日程，或设置 1–480 分钟专注"); return
                }
                let state = FlowActivityAttributes.ContentState(title: args.title, start: start, end: end)
                let content = ActivityContent(state: state, staleDate: end)
                let existing = Activity<FlowActivityAttributes>.activities
                if let current = existing.first(where: {
                    $0.attributes.scope == args.scope && $0.attributes.eventId == args.eventId &&
                    ($0.activityState == .active || $0.activityState == .stale)
                }) {
                    await current.update(content)
                    for other in existing where other.id != current.id { await other.end(nil, dismissalPolicy: .immediate) }
                } else {
                    do {
                        _ = try Activity.request(attributes: FlowActivityAttributes(scope: args.scope, eventId: args.eventId), content: content, pushType: nil)
                        for old in existing { await old.end(nil, dismissalPolicy: .immediate) }
                    } catch { invoke.reject("无法启动实时活动：\(error.localizedDescription)"); return }
                }
                invoke.resolve(self.snapshot())
            }
        } catch { invoke.reject("实时活动参数无效") }
    }
    @objc func end(_ invoke: Invoke) {
        enqueue {
            if #available(iOS 16.2, *) {
                for activity in Activity<FlowActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                invoke.resolve(self.snapshot())
            } else { invoke.resolve(["supported": false, "enabled": false, "active": NSNull()]) }
        }
    }
}
@_cdecl("init_plugin_live_activity")
func initPlugin() -> Plugin { LiveActivityPlugin() }
