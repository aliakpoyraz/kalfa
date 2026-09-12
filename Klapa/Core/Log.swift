import OSLog

enum Log {
    private static let subsystem = "com.aliakpoyraz.klapa"

    static let display = Logger(subsystem: subsystem, category: "display")
    static let profile = Logger(subsystem: subsystem, category: "profile")
    static let ddc     = Logger(subsystem: subsystem, category: "ddc")
}
