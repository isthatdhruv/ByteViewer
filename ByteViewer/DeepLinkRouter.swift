import Combine
import Foundation
import UIKit

enum DeepLinkRequest: Equatable {
    case site(UUID)
    case url(URL)
}

/// Receives open requests from URLs, Quick Actions, the widget and Shortcuts, and hands
/// them to the UI.
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    static let shortcutType = "com.example.ByteViewer.open-site"

    @Published var request: DeepLinkRequest?

    private init() {}

    /// Handles `byteviewer://open?site=<uuid>` and `byteviewer://open?url=<address>`.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard url.scheme?.lowercased() == "byteviewer" else { return false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let raw = items.first(where: { $0.name == "site" })?.value, let id = UUID(uuidString: raw) {
            request = .site(id)
            return true
        }
        if let raw = items.first(where: { $0.name == "url" })?.value,
           let target = Site.normalize(raw, allowHTTP: true) {
            request = .url(target)
            return true
        }
        return false
    }

    @discardableResult
    func handle(shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard shortcutItem.type == Self.shortcutType,
              let raw = shortcutItem.userInfo?["site"] as? String,
              let id = UUID(uuidString: raw) else { return false }
        request = .site(id)
        return true
    }

    /// Long-press menu on the app icon: the first four sites in the list.
    static func updateQuickActions(with sites: [Site]) {
        UIApplication.shared.shortcutItems = sites.prefix(4).map { site in
            UIApplicationShortcutItem(
                type: shortcutType,
                localizedTitle: site.displayName,
                localizedSubtitle: site.host,
                icon: UIApplicationShortcutIcon(systemImageName: "globe"),
                userInfo: ["site": site.id.uuidString as NSString]
            )
        }
    }
}
