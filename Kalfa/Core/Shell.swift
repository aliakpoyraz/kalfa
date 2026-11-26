import Foundation

/// Runs a short command and returns what it printed.
///
/// It deliberately does not call `Process.waitUntilExit()`. That method waits by
/// spinning the current run loop, and on the main thread the run loop is where
/// SwiftUI flushes its pending updates. A command started while a view was being
/// built — a `defaults read` behind a `@State` default, `networksetup` behind a
/// shared service's first use — let SwiftUI start a second update inside the
/// first one. It showed up as two different crashes with the same cause: an
/// AttributeGraph precondition failure on the Desktop page, and a `dispatch_once`
/// re-entry on the Network page.
///
/// So the wait here is a plain blocking one. The pipe is drained first, which
/// already lasts until the command closes its output; the short poll after it
/// only covers the gap between that and the exit status being available.
enum Shell: Sendable {

    nonisolated static func result(_ path: String, _ arguments: [String], timeout: TimeInterval = 15) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            usleep(5_000)
        }
        if process.isRunning { process.terminate() }
        return String(decoding: data, as: UTF8.self)
    }
}
