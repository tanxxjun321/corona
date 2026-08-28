import CoronaCore

final class RecordingDiagnosticLogger: DiagnosticLogging {
    private(set) var events: [DiagnosticEvent] = []

    func log(_ event: DiagnosticEvent) {
        events.append(event)
    }

    var warnings: [String] {
        events.compactMap { event in
            if case .warning(let message) = event {
                return message
            }
            return nil
        }
    }
}
