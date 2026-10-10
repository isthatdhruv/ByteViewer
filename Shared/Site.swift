import Foundation
import SwiftUI
import UIKit

// This file is compiled into both the app and the widget extension, so it must only use
// extension-safe API (no UIApplication).

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
    var id: UUID
    var name: String
    var url: String
    /// Request the desktop version of the site (desktop user agent + layout).
    var desktopMode: Bool
    /// Hide the status bar and auto-hide the home indicator.
    var hideStatusBar: Bool
    /// Force `viewport-fit=cover` so the page draws under the notch / home indicator.
    var edgeToEdge: Bool
    var orientation: OrientationMode
    /// Links to other domains open in Safari instead of inside the app.
    var stayInSite: Bool
    /// Keep the screen from sleeping while the site is open.
    var keepAwake: Bool
    /// Controls hidden, swipe navigation off, status bar hidden; device authentication reveals controls.
    var kioskMode: Bool
    /// Face ID / Touch ID / passcode before the site is shown.
    var requiresAuth: Bool
    /// No cookies or site data are kept between visits.
    var privateMode: Bool
    /// Let plain http:// URLs load instead of upgrading them to https://.
    var allowHTTP: Bool
    /// CSS colour from the site's `theme-color` meta tag, when known.
    var themeColor: String?

    init(id: UUID = UUID(), name: String, url: String, desktopMode: Bool = false) {
        self.id = id
        self.name = name
        self.url = url
        self.desktopMode = desktopMode
        hideStatusBar = false
        edgeToEdge = false
        orientation = .auto
        stayInSite = false
        keepAwake = false
        kioskMode = false
        requiresAuth = false
        privateMode = false
        allowHTTP = false
        themeColor = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, url, desktopMode, hideStatusBar, edgeToEdge, orientation
        case stayInSite, keepAwake, kioskMode, requiresAuth, privateMode, allowHTTP, themeColor
    }

    /// Tolerant decoding so sites saved by older versions keep loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try c.decode(String.self, forKey: .url)
        desktopMode = try c.decodeIfPresent(Bool.self, forKey: .desktopMode) ?? false
        hideStatusBar = try c.decodeIfPresent(Bool.self, forKey: .hideStatusBar) ?? false
        edgeToEdge = try c.decodeIfPresent(Bool.self, forKey: .edgeToEdge) ?? false
        orientation = try c.decodeIfPresent(OrientationMode.self, forKey: .orientation) ?? .auto
        stayInSite = try c.decodeIfPresent(Bool.self, forKey: .stayInSite) ?? false
        keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? false
        kioskMode = try c.decodeIfPresent(Bool.self, forKey: .kioskMode) ?? false
        requiresAuth = try c.decodeIfPresent(Bool.self, forKey: .requiresAuth) ?? false
        privateMode = try c.decodeIfPresent(Bool.self, forKey: .privateMode) ?? false
        allowHTTP = try c.decodeIfPresent(Bool.self, forKey: .allowHTTP) ?? false
        themeColor = try c.decodeIfPresent(String.self, forKey: .themeColor)
    }

    var resolvedURL: URL? { Site.normalize(url, allowHTTP: allowHTTP) }

    var host: String? { resolvedURL?.host?.lowercased() }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return host ?? url
    }

    /// URL that opens this site from the widget, Shortcuts or a home-screen launcher.
    var deepLink: URL {
        URL(string: "byteviewer://open?site=\(id.uuidString)")!
    }

    /// Turns "example.com/path" into "https://example.com/path". Plain http:// is upgraded
    /// to https:// unless `allowHTTP` is set.
    static func normalize(_ raw: String, allowHTTP: Bool = false) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("http://") {
            if !allowHTTP {
                text = "https://" + text.dropFirst("http://".count)
            }
        } else if !lower.hasPrefix("https://") {
            text = "https://" + text
        }
        guard let url = URL(string: text), let host = url.host,
              host.contains(".") || host == "localhost" else {
            return nil
        }
        return url
    }

    /// True when `other` is this site's host or one of its subdomains ("www." is ignored).
    func owns(host other: String?) -> Bool {
        guard let mine = host, let other = other?.lowercased() else { return false }
        let a = Site.stripWWW(mine)
        let b = Site.stripWWW(other)
        return a == b || b.hasSuffix("." + a)
    }

    /// True when a WebKit data record (named by registrable domain, e.g. "example.com") belongs to this site.
    func matchesDataRecord(named record: String) -> Bool {
        guard let mine = host else { return false }
        let a = Site.stripWWW(mine)
        let b = Site.stripWWW(record.lowercased())
        return a == b || a.hasSuffix("." + b) || b.hasSuffix("." + a)
    }

    private static func stripWWW(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// The site list as shared between the app, the widget and Shortcuts.
enum SharedSites {
    static let key = "sites.v1"

    /// The app's own copy first, then the App Group copy (what the widget sees).
    static func load() -> [Site] {
        let own = load(from: .standard)
        return own.isEmpty ? load(from: AppGroup.defaults) : own
    }

    static func load(from defaults: UserDefaults) -> [Site] {
        guard let data = defaults.data(forKey: key),
              let sites = try? JSONDecoder().decode([Site].self, from: data) else {
            return []
        }
        return sites
    }

    static func save(_ sites: [Site], to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(sites) {
            defaults.set(data, forKey: key)
        }
    }
}

/// The App Group that the app and the widget share.
enum AppGroup {
    static let defaultIdentifier = "group.com.example.ByteViewer"

    /// The group this build was actually signed with. Sideloading tools usually rewrite the
    /// group id when they re-sign the app, so read it from the embedded provisioning profile.
    static let identifier: String = {
        if let groups = embeddedEntitlements()?["com.apple.security.application-groups"] as? [String],
           let first = groups.first {
            return first
        }
        return defaultIdentifier
    }()

    static let defaults: UserDefaults = UserDefaults(suiteName: identifier) ?? .standard

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    private static func embeddedEntitlements() -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<plist".utf8)),
              let end = data.range(of: Data("</plist>".utf8)),
              start.lowerBound < end.upperBound else {
            return nil
        }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
              let dict = plist as? [String: Any] else {
            return nil
        }
        return dict["Entitlements"] as? [String: Any]
    }
}

/// Cached site icons, stored in the App Group container so the widget can show them too.
enum IconStore {
    static var directory: URL {
        let base = AppGroup.containerURL
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("SiteIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString + ".png")
    }

    static func image(for id: UUID) -> UIImage? {
        UIImage(contentsOfFile: url(for: id).path)
    }

    static func save(_ image: UIImage, for id: UUID) {
        if let data = image.pngData() {
            try? data.write(to: url(for: id), options: .atomic)
        }
    }

    static func remove(for id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }
}

/// Parses the CSS colour from a `theme-color` meta tag.
enum ThemeColor {
    static func uiColor(from css: String?) -> UIColor? {
        guard var s = css?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !s.isEmpty else {
            return nil
        }
        if s.hasPrefix("#") {
            s.removeFirst()
            var hex = s
            if hex.count == 3 || hex.count == 4 {
                hex = hex.map { "\($0)\($0)" }.joined()
            }
            guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
            if hex.count == 8 {
                return UIColor(red: CGFloat((value >> 24) & 0xff) / 255,
                               green: CGFloat((value >> 16) & 0xff) / 255,
                               blue: CGFloat((value >> 8) & 0xff) / 255,
                               alpha: CGFloat(value & 0xff) / 255)
            }
            return UIColor(red: CGFloat((value >> 16) & 0xff) / 255,
                           green: CGFloat((value >> 8) & 0xff) / 255,
                           blue: CGFloat(value & 0xff) / 255,
                           alpha: 1)
        }
        if s.hasPrefix("rgb") {
            let numbers = s.components(separatedBy: CharacterSet(charactersIn: "(),/ "))
                .compactMap { Double($0.replacingOccurrences(of: "%", with: "")) }
            guard numbers.count >= 3 else { return nil }
            return UIColor(red: numbers[0] / 255, green: numbers[1] / 255, blue: numbers[2] / 255,
                           alpha: numbers.count > 3 ? min(numbers[3], 1) : 1)
        }
        let named: [String: UIColor] = ["black": .black, "white": .white, "red": .red, "blue": .blue,
                                        "green": .green, "gray": .gray, "grey": .gray]
        return named[s]
    }

    static func color(from css: String?) -> Color? {
        uiColor(from: css).map { Color(uiColor: $0) }
    }

    static func isDark(_ color: UIColor) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r + 0.587 * g + 0.114 * b) < 0.6
    }
}
