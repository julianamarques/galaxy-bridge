import Foundation

extension Bundle {
    public static var appName: String {
        main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Samsung for Mac"
    }
}
