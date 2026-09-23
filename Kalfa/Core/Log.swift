import OSLog

enum Log {
    private static let subsystem = "com.aliakpoyraz.kalfa"

    static let display = Logger(subsystem: subsystem, category: "display")
    static let profile = Logger(subsystem: subsystem, category: "profile")
    static let ddc     = Logger(subsystem: subsystem, category: "ddc")
    static let scroll  = Logger(subsystem: subsystem, category: "scroll")
}
