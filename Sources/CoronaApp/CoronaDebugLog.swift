import Foundation
import os

enum CoronaDebugLog {
    private static let logger = Logger(subsystem: "com.ltz.corona", category: "debug")
    private static let queue = DispatchQueue(label: "com.ltz.corona.debug-log")

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Corona/Corona-debug.log")
    }

    static func log(_ message: String) {
        let line = "[\(timestamp())] \(message)\n"
        logger.debug("\(message)")
        queue.async {
            do {
                let directory = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let handle = try FileHandle(forWritingTo: fileURL)
                    try handle.seekToEnd()
                    if let data = line.data(using: .utf8) {
                        try handle.write(contentsOf: data)
                    }
                    try handle.close()
                } else {
                    try line.write(to: fileURL, atomically: true, encoding: .utf8)
                }
            } catch {
                logger.error("Debug log write failed: \(String(describing: error))")
            }
        }
    }

    static func verbose(_ message: String) {
        guard UserDefaults.standard.bool(forKey: "Settings.enableDiagnosticLogging") else { return }
        log(message)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
