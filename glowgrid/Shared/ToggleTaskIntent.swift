import AppIntents
import Foundation

/// Tapping the circle in the widget runs this, without opening the app.
struct ToggleTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "完成事项"

    @Parameter(title: "事项")
    var taskID: String

    init() {}

    init(taskID: String) {
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: taskID) {
            TaskStore.toggle(id)
        }
        return .result()
    }
}
