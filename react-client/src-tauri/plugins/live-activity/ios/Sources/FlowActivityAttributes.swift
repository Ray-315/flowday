import ActivityKit
import Foundation

@available(iOS 16.2, *)
struct FlowActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var start: Date
        var end: Date
    }
    var scope: String
    var eventId: String?
    var upcoming: Bool?
}
