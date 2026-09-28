import Foundation

enum AppLinks {
    static let contactEmail = "zhaoweijia1997@gmail.com"

    /// Set once the GitHub repository exists, e.g. "https://github.com/<user>/Sweeply".
    /// The About window hides the GitHub and support links while this is nil.
    static let repository: URL? = nil

    /// The "Support Sweeply" section of the README.
    static var support: URL? {
        repository.flatMap { URL(string: $0.absoluteString + "#support-sweeply") }
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
