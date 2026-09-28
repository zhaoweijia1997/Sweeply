import Foundation

enum AppLinks {
    static let contactEmail = "zhaoweijia1997@gmail.com"

    /// The About window hides the GitHub and support links when this is nil.
    static let repository: URL? = URL(string: "https://github.com/zhaoweijia1997/Sweeply")

    /// The "Support Sweeply" section of the README.
    static var support: URL? {
        repository.flatMap { URL(string: $0.absoluteString + "#support-sweeply") }
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
