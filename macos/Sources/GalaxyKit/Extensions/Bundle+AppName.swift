import Foundation

extension Bundle {
    public static var appName: String {
        main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Galaxy"
    }

    public static var appVersion: String? {
        main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}
