import Foundation
import os

enum CoronaDebugLog {
    private static let logger = Logger(subsystem: "com.ltz.corona", category: "debug")
    private static let queue = DispatchQueue(label: "com.ltz.corona.debug-log")

    /// Upper bound for the on-disk log. When a write would push the file past
    /// this size, the file is renamed to `Corona-debug.log.old` (replacing any
    /// previous `.old`) and a fresh file is started — the simplest rotation
    /// scheme that keeps the log bounded.
    private static let maxFileSize: UInt64 = 5 * 1024 * 1024

    /// Reused formatter: allocating an ISO8601DateFormatter per line was a
    /// measurable cost in the hot logging path.
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Long-lived append handle, only touched on `queue`. FileHandle writes
    /// are direct syscalls, so there is nothing to flush at process exit.
    private static var fileHandle: FileHandle?

    /// Byte size of the log file, kept in sync with writes via `fileHandle`.
    private static var currentFileSize: UInt64 = 0

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Corona/Corona-debug.log")
    }

    static func log(_ message: String) {
        logger.debug("\(message)")
        // File logging is gated behind the diagnostic setting (default off):
        // with the gate closed we must not create or append to the log file.
        // The check runs per call, so toggling the setting takes effect
        // immediately without any refresh mechanism.
        guard UserDefaults.standard.bool(forKey: "Settings.enableDiagnosticLogging") else { return }
        let line = "[\(timestampFormatter.string(from: Date()))] \(message)\n"
        queue.async {
            appendLine(line)
        }
    }

    static func verbose(_ message: String) {
        guard UserDefaults.standard.bool(forKey: "Settings.enableDiagnosticLogging") else { return }
        log(message)
    }

    /// Only ever called on `queue`.
    private static func appendLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        do {
            if fileHandle == nil {
                try openFile()
            }
            if currentFileSize + UInt64(data.count) > maxFileSize {
                try rotateFile()
            }
            try fileHandle?.write(contentsOf: data)
            currentFileSize += UInt64(data.count)
        } catch {
            logger.error("Debug log write failed: \(String(describing: error))")
        }
    }

    /// Only ever called on `queue`.
    private static func openFile() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        currentFileSize = handle.seekToEndOfFile()
        fileHandle = handle
    }

    /// Only ever called on `queue`.
    private static func rotateFile() throws {
        if let handle = fileHandle {
            try? handle.close()
            fileHandle = nil
        }
        let oldURL = fileURL.appendingPathExtension("old")
        try? FileManager.default.removeItem(at: oldURL)
        try FileManager.default.moveItem(at: fileURL, to: oldURL)
        currentFileSize = 0
        try openFile()
    }
}
