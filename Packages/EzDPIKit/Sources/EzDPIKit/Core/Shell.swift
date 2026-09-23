import Foundation

struct ShellResult {
    let status: Int32
    let stdout: String
    let stderr: String
    var ok: Bool { status == 0 }
}

/// Kısa ömürlü komut çalıştırıcı. Motor süreci bunu KULLANMAZ; onun kendi
/// uzun ömürlü Process yönetimi var (Engine.swift).
enum Shell {
    @discardableResult
    static func run(_ launchPath: String, _ args: [String], timeout: TimeInterval = 20) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            return ShellResult(status: -1, stdout: "", stderr: "\(error)")
        }

        // Pipe'ları süreç bitmeden okumazsak 64KB'ı aşan çıktıda kilitleniriz.
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            return ShellResult(status: -2, stdout: String(decoding: outData, as: UTF8.self), stderr: "zaman aşımı")
        }

        return ShellResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    @discardableResult
    static func networksetup(_ args: [String]) -> ShellResult {
        run("/usr/sbin/networksetup", args)
    }
}
