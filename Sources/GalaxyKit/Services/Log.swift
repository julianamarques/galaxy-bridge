import OSLog

public enum Log {
    public static let subsystem = Bundle.main.bundleIdentifier ?? "com.julianamarques.SamsungForMac"
    public static let adb = Logger(subsystem: subsystem, category: "adb")
    public static let connection = Logger(subsystem: subsystem, category: "connection")
    public static let phone = Logger(subsystem: subsystem, category: "phone")
}
