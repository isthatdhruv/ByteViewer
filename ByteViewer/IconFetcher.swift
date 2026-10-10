import Foundation
import UIKit

/// Icon links and theme colour discovered on a page.
struct PageMetadata {
    var iconURLs: [URL]
    var themeColor: String?
}

/// Finds a site's icon (apple-touch-icon, favicon) and theme colour, and caches the icon.
enum IconFetcher {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    /// Downloads the page HTML and looks for icon links and a theme colour. Completion on main.
    static func fetch(for site: Site, completion: @escaping (PageMetadata?) -> Void) {
        guard let url = site.resolvedURL else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.setValue(UserAgent.string(desktop: false), forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { data, response, _ in
            let base = response?.url ?? url
            var metadata = PageMetadata(iconURLs: [], themeColor: nil)
            if let data,
               let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                metadata = parse(html: String(html.prefix(300_000)), base: base)
            }
            metadata.iconURLs.append(contentsOf: fallbackIcons(for: base))
            DispatchQueue.main.async { completion(metadata) }
        }.resume()
    }

    /// Well-known icon locations at the site root, tried after anything the page declares.
    static func fallbackIcons(for url: URL) -> [URL] {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
        comps.path = ""
        comps.query = nil
        comps.fragment = nil
        guard let root = comps.url else { return [] }
        return [root.appendingPathComponent("apple-touch-icon.png"),
                root.appendingPathComponent("favicon.ico")]
    }

    static func parse(html: String, base: URL) -> PageMetadata {
        var touch: [URL] = []
        var plain: [URL] = []
        for tag in tags(named: "link", in: html) {
            guard let rel = attribute("rel", in: tag)?.lowercased(),
                  let href = attribute("href", in: tag),
                  let url = URL(string: href, relativeTo: base)?.absoluteURL else { continue }
            if rel.contains("apple-touch-icon") {
                touch.append(url)
            } else if rel.split(separator: " ").contains("icon") {
                plain.append(url)
            }
        }
        var theme: String?
        for tag in tags(named: "meta", in: html) {
            if attribute("name", in: tag)?.lowercased() == "theme-color",
               let content = attribute("content", in: tag) {
                theme = content
                break
            }
        }
        return PageMetadata(iconURLs: touch + plain, themeColor: theme)
    }

    private static func tags(named name: String, in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "<" + name + "\\b[^>]*>", options: [.caseInsensitive]) else {
            return []
        }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b" + name + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = tag as NSString
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)) else { return nil }
        for group in 1...3 {
            let range = match.range(at: group)
            if range.location != NSNotFound {
                return ns.substring(with: range).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Tries each candidate in order until one decodes as an image, then caches it. Completion on main.
    static func download(candidates: [URL], for id: UUID, completion: @escaping (Bool) -> Void) {
        var queue = candidates
        func tryNext() {
            guard !queue.isEmpty else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let url = queue.removeFirst()
            session.dataTask(with: url) { data, response, _ in
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                   let data, let image = UIImage(data: data), image.size.width >= 16 {
                    IconStore.save(resized(image, to: 180), for: id)
                    DispatchQueue.main.async { completion(true) }
                } else {
                    tryNext()
                }
            }.resume()
        }
        tryNext()
    }

    private static func resized(_ image: UIImage, to side: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > side else { return image }
        let scale = side / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
