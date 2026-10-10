import Combine
import Foundation
import UIKit

/// How the screen should be held while a site is open.
enum OrientationMode: String, Codable, CaseIterable, Identifiable {
    case auto, portrait, landscape

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .portrait: return "Portrait"
        case .landscape: return "Landscape"
        }
    }

    var mask: UIInterfaceOrientationMask {
        switch self {
        case .auto: return .all
        case .portrait: return .portrait
        case .landscape: return .landscape
        }
    }
}

/// A saved website and the way it should be displayed.
struct Site: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var url: String
    /// Request the desktop version of the site (desktop user agent + layout).
    var desktopMode: Bool = false
    /// Hide the status bar and auto-hide the home indicator.
    var hideStatusBar: Bool = false
    /// Force `viewport-fit=cover` so the page draws under the notch / home indicator.
    var edgeToEdge: Bool = false
    var orientation: OrientationMode = .auto

    var resolvedURL: URL? { Site.normalize(url) }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return resolvedURL?.host ?? url
    }

    /// Turns "example.com/path" into "https://example.com/path". HTTPS only.
    static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        let lower = text.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            text = "https://" + text
        }
        guard let url = URL(string: text), let host = url.host, host.contains(".") || host == "localhost" else {
            return nil
        }
        return url
    }
}

/// Persists the list of sites in UserDefaults.
final class SiteStore: ObservableObject {
    @Published var sites: [Site] {
        didSet { save() }
    }

    /// Site that opens automatically when the app launches ("" = none).
    @Published var autoOpenSiteID: String {
        didSet { UserDefaults.standard.set(autoOpenSiteID, forKey: Self.autoOpenKey) }
    }

    private static let sitesKey = "sites.v1"
    private static let autoOpenKey = "autoOpenSiteID"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.sitesKey),
           let decoded = try? JSONDecoder().decode([Site].self, from: data) {
            sites = decoded
        } else {
            sites = []
        }
        autoOpenSiteID = UserDefaults.standard.string(forKey: Self.autoOpenKey) ?? ""
    }

    var autoOpenSite: Site? {
        sites.first { $0.id.uuidString == autoOpenSiteID }
    }

    func add(_ site: Site) {
        sites.append(site)
    }

    func update(_ site: Site) {
        if let index = sites.firstIndex(where: { $0.id == site.id }) {
            sites[index] = site
        }
    }

    func remove(_ site: Site) {
        sites.removeAll { $0.id == site.id }
        if autoOpenSiteID == site.id.uuidString {
            autoOpenSiteID = ""
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        sites.move(fromOffsets: source, toOffset: destination)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sites) {
            UserDefaults.standard.set(data, forKey: Self.sitesKey)
        }
    }
}
