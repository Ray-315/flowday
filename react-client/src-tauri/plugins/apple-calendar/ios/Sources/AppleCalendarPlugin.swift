import Tauri
import FlowCalendarCore
import Foundation
private struct Args: Decodable { let json: String }
class AppleCalendarPlugin: Plugin {
    @objc func request(_ invoke: Invoke) {
        do {
            let args = try invoke.parseArgs(Args.self)
            FlowCalendarCore.run(args.json) { result in
                guard let data = result.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    invoke.reject("日历返回无效数据"); return
                }
                invoke.resolve(object)
            }
        } catch { invoke.reject("日历参数无效") }
    }
}
@_cdecl("init_plugin_apple_calendar")
func initPlugin() -> Plugin { AppleCalendarPlugin() }
