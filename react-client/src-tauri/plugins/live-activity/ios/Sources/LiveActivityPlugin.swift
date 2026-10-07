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

private struct ScheduleArgs: Decodable {
    struct Event: Decodable { let eventId: String; let title: String; let start: Double }
    let scope: String
    let minutes: Int
    let event: Event?
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
        let all = Activity<FlowActivityAttributes>.activities
        func value(_ activity: Activity<FlowActivityAttributes>?) -> Any {
            guard let a = activity else { return NSNull() }
            let state = a.content.state
            return ["title": state.title, "start": state.start.timeIntervalSince1970 * 1000,
                    "end": state.end.timeIntervalSince1970 * 1000, "scope": a.attributes.scope,
                    "eventId": a.attributes.eventId as Any? ?? NSNull(), "upcoming": a.attributes.upcoming == true] as [String: Any]
        }
        let current = all.first { ($0.activityState == .active || $0.activityState == .stale) && $0.content.state.end > Date() }
        var scheduled: Activity<FlowActivityAttributes>?
        var autoScheduling = false
        if #available(iOS 26.0, *) {
            autoScheduling = true
            scheduled = all.first { $0.attributes.upcoming == true && ($0.activityState == .pending || $0.activityState == .active) && $0.content.state.end > Date() }
        }
        return ["supported": true, "enabled": ActivityAuthorizationInfo().areActivitiesEnabled,
                "active": value(current), "scheduled": value(scheduled), "autoScheduling": autoScheduling]
    }
    @objc func schedule(_ invoke: Invoke) {
        do {
            let args = try invoke.parseArgs(ScheduleArgs.self)
            enqueue {
                guard #available(iOS 26.0, *) else { invoke.reject("自动预约需要 iOS 26 或更新版本"); return }
                guard !args.scope.isEmpty, (1...120).contains(args.minutes) else { invoke.reject("请设置提前 1–120 分钟"); return }
                let all = Activity<FlowActivityAttributes>.activities.filter { $0.attributes.upcoming == true }
                let key = "flowday.lastScheduledActivity"
                guard let event = args.event else {
                    for a in all { await a.end(nil, dismissalPolicy: .immediate) }
                    UserDefaults.standard.removeObject(forKey: key)
                    invoke.resolve(self.snapshot()); return
                }
                let now = Date(), target = Date(timeIntervalSince1970: event.start / 1000)
                guard event.start.isFinite, target > now.addingTimeInterval(3), !event.title.isEmpty, event.title.count <= 120 else { invoke.reject("下一个日程时间或标题无效"); return }
                let begin = target.addingTimeInterval(Double(-args.minutes * 60))
                let signature = String(data: try! JSONEncoder().encode([args.scope, event.eventId, event.title, String(event.start), String(args.minutes)]), encoding: .utf8)!
                if let existing = all.first(where: { $0.attributes.scope == args.scope && $0.attributes.eventId == event.eventId && $0.content.state.title == event.title && $0.content.state.start == begin && $0.content.state.end == target && ($0.activityState == .pending || $0.activityState == .active) }) {
                    for a in all where a.id != existing.id { await a.end(nil, dismissalPolicy: .immediate) }
                    invoke.resolve(self.snapshot()); return
                }
                // A dismissed reservation must not reappear on each foreground refresh.
                if UserDefaults.standard.string(forKey: key) == signature && !all.contains(where: { $0.activityState == .pending || $0.activityState == .active }) { invoke.resolve(self.snapshot()); return }
                guard ActivityAuthorizationInfo().areActivitiesEnabled else { invoke.reject("请允许 FlowDay 实时活动后重试"); return }
                for a in all { await a.end(nil, dismissalPolicy: .immediate) }
                let content = ActivityContent(state: FlowActivityAttributes.ContentState(title: event.title, start: begin, end: target), staleDate: target)
                do {
                    _ = try Activity.request(attributes: FlowActivityAttributes(scope: args.scope, eventId: event.eventId, upcoming: true), content: content, pushType: nil, style: .standard,
                        alertConfiguration: AlertConfiguration(title: "日程即将开始", body: "\(event.title)", sound: .default), start: max(begin, now.addingTimeInterval(2)))
                    UserDefaults.standard.set(signature, forKey: key)
                    invoke.resolve(self.snapshot())
                } catch { invoke.reject("无法预约灵动岛提醒：\(error.localizedDescription)") }
            }
        } catch { invoke.reject("自动提醒参数无效") }
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
                    $0.attributes.upcoming != true && $0.attributes.scope == args.scope && $0.attributes.eventId == args.eventId &&
                    ($0.activityState == .active || $0.activityState == .stale)
                }) {
                    await current.update(content)
                    for other in existing where other.id != current.id && other.attributes.upcoming != true { await other.end(nil, dismissalPolicy: .immediate) }
                } else {
                    do {
                        _ = try Activity.request(attributes: FlowActivityAttributes(scope: args.scope, eventId: args.eventId), content: content, pushType: nil)
                        for old in existing where old.attributes.upcoming != true { await old.end(nil, dismissalPolicy: .immediate) }
                    } catch { invoke.reject("无法启动实时活动：\(error.localizedDescription)"); return }
                }
                invoke.resolve(self.snapshot())
            }
        } catch { invoke.reject("实时活动参数无效") }
    }
    @objc func end(_ invoke: Invoke) {
        enqueue {
            UserDefaults.standard.removeObject(forKey: "flowday.lastScheduledActivity")
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
