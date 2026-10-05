import Foundation
import EventKit

public enum FlowCalendarCore {
    private static let store = EKEventStore()
    private static let queue = DispatchQueue(label: "pro.flowday.calendar")
    public static func run(_ raw: String, completion: @escaping (String) -> Void) {
        func finish(_ value: [String: Any]) {
            let data = (try? JSONSerialization.data(withJSONObject: value)) ?? Data("{}".utf8)
            completion(String(decoding: data, as: UTF8.self))
        }
        guard let data = raw.data(using: .utf8), let args = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            finish(["error": "日历参数无效"]); return
        }
        if args["action"] as? String == "capability" { finish(["supported": true]); return }
        let permitted: (Bool, Error?) -> Void = { granted, error in
            guard granted else { finish(["error": "未获得日历完整访问权限，请在系统设置 → 隐私与安全 → 日历中允许 FlowDay 后重试"]); return }
            queue.async {
                do { finish(try perform(args)) }
                catch { finish(["error": error.localizedDescription]) }
            }
        }
        DispatchQueue.main.async {
            if #available(iOS 17, macOS 14, *) { store.requestFullAccessToEvents(completion: permitted) }
            else { store.requestAccess(to: .event, completion: permitted) }
        }
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "FlowDay.Calendar", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private static func snapshot(_ event: EKEvent) -> [String: Any] {
        ["identifier": event.eventIdentifier ?? "", "externalId": event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? "",
         "occurrence": (event.occurrenceDate ?? event.startDate).timeIntervalSince1970 * 1000,
         "recurring": event.hasRecurrenceRules || event.isDetached,
         "title": event.title ?? "无标题日程", "start": event.startDate.timeIntervalSince1970 * 1000,
         "end": event.endDate.timeIntervalSince1970 * 1000, "allDay": event.isAllDay,
         "location": event.location ?? "", "notes": event.notes ?? "", "url": event.url?.absoluteString ?? ""]
    }
    private static func events(_ calendar: EKCalendar, from: Date, to: Date) -> [EKEvent] {
        store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: [calendar]))
    }
    private static func perform(_ args: [String: Any]) throws -> [String: Any] {
        store.refreshSourcesIfNecessary()
        let calendars = store.calendars(for: .event)
        guard let action = args["action"] as? String else { throw failure("日历操作无效") }
        if action == "calendars" {
            return ["calendars": calendars.map { ["id": $0.calendarIdentifier, "title": $0.title,
                "account": $0.source.title, "writable": $0.allowsContentModifications] as [String: Any] }]
        }
        guard let calendarId = args["calendarId"] as? String,
              let calendar = calendars.first(where: { $0.calendarIdentifier == calendarId }) else { throw failure("找不到所选日历，请重新选择") }
        if action == "read" {
            guard let from = args["from"] as? Double, let to = args["to"] as? Double,
                  from.isFinite, to.isFinite, to > from, to - from <= 400 * 86400000 else { throw failure("同步范围不能超过 400 天") }
            let result = events(calendar, from: Date(timeIntervalSince1970: from / 1000), to: Date(timeIntervalSince1970: to / 1000))
            guard result.count <= 2000 else { throw failure("此范围日程超过 2000 条，请缩小同步日期范围") }
            return ["events": result.map(snapshot)]
        }
        guard action == "save", calendar.allowsContentModifications,
              let value = args["event"] as? [String: Any], let title = value["title"] as? String,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 2000,
              let start = value["start"] as? Double, let end = value["end"] as? Double,
              start.isFinite, end.isFinite, end > start else { throw failure("日历不可写，或日程内容无效") }
        let event: EKEvent
        if let expected = args["expected"] as? [String: Any], let identifier = expected["identifier"] as? String,
           let oldStart = expected["start"] as? Double, let occurrence = expected["occurrence"] as? Double {
            let matches = events(calendar, from: Date(timeIntervalSince1970: oldStart / 1000 - 86400), to: Date(timeIntervalSince1970: oldStart / 1000 + 86400))
            guard let found = matches.first(where: {
                $0.eventIdentifier == identifier && abs(($0.occurrenceDate ?? $0.startDate).timeIntervalSince1970 * 1000 - occurrence) < 1
            }) else { throw failure("苹果日程已移动或删除，请重新同步") }
            let current = snapshot(found)
            for key in ["title", "start", "end", "allDay", "location", "notes", "url"] {
                guard (current[key] as? NSObject)?.isEqual(expected[key]) == true else {
                    throw failure("苹果日程刚刚发生变化，请重新同步后处理冲突")
                }
            }
            event = found
        } else {
            guard let marker = value["url"] as? String, marker.hasPrefix("flowday://calendar/") else { throw failure("新日程缺少同步标识") }
            let existing = events(calendar, from: Date(timeIntervalSince1970: start / 1000 - 86400), to: Date(timeIntervalSince1970: end / 1000 + 86400)).first { $0.url?.absoluteString == marker }
            if let existing = existing {
                let current = snapshot(existing)
                for key in ["title", "start", "end", "allDay", "location", "notes"] {
                    guard (current[key] as? NSObject)?.isEqual(value[key]) == true else {
                        throw failure("已存在的苹果日程内容不同，请重新同步后处理冲突")
                    }
                }
                return ["event": current]
            }
            event = EKEvent(eventStore: store); event.calendar = calendar; event.url = URL(string: marker)
        }
        event.title = title
        event.startDate = Date(timeIntervalSince1970: start / 1000)
        event.endDate = Date(timeIntervalSince1970: end / 1000)
        event.isAllDay = value["allDay"] as? Bool ?? false
        event.location = value["location"] as? String ?? ""
        event.notes = value["notes"] as? String ?? ""
        // Edit only this occurrence. Keep attendees, alarms, URL and other Apple metadata.
        try store.save(event, span: .thisEvent, commit: true)
        return ["event": snapshot(event)]
    }
}
#if os(macOS)
@_cdecl("flow_calendar_run")
public func flowCalendarRun(_ raw: UnsafePointer<CChar>, _ callback: @escaping @convention(c) (UnsafePointer<CChar>, UnsafeMutableRawPointer?) -> Void, _ context: UnsafeMutableRawPointer?) {
    FlowCalendarCore.run(String(cString: raw)) { result in result.withCString { callback($0, context) } }
}
#endif
