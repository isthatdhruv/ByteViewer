import Combine
import Foundation
import UIKit
import WebKit
import WidgetKit

/// Persists the list of sites and mirrors it to the App Group for the widget and Shortcuts.
final class SiteStore: ObservableObject {
    @Published var sites: [Site] {
        didSet { save() }
    }

    /// Site that opens automatically when the app launches ("" = none).
    @Published var autoOpenSiteID: String {
        didSet { UserDefaults.standard.set(autoOpenSiteID, forKey: Self.autoOpenKey) }
    }

    /// Bumped whenever an icon file changes so rows showing icons refresh.
    @Published var iconVersion = 0

    private static let autoOpenKey = "autoOpenSiteID"

    init() {
        sites = SharedSites.load(from: .standard)
        autoOpenSiteID = UserDefaults.standard.string(forKey: Self.autoOpenKey) ?? ""
        SharedSites.save(sites, to: AppGroup.defaults)
        refreshMissingIcons()
    }

    var autoOpenSite: Site? {
        sites.first { $0.id.uuidString == autoOpenSiteID }
    }

    func site(id: UUID) -> Site? {
        sites.first { $0.id == id }
    }

    func add(_ site: Site) {
        sites.append(site)
        fetchMetadata(for: site)
    }

    func update(_ site: Site) {
        guard let index = sites.firstIndex(where: { $0.id == site.id }) else { return }
        let previous = sites[index]
        sites[index] = site
        if previous.url != site.url {
            fetchMetadata(for: site)
        }
    }

    func remove(_ site: Site) {
        sites.removeAll { $0.id == site.id }
        IconStore.remove(for: site.id)
        if autoOpenSiteID == site.id.uuidString {
            autoOpenSiteID = ""
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        sites.move(fromOffsets: source, toOffset: destination)
    }

    /// Called after a page of the site loaded; keeps the icon and theme colour fresh.
    func apply(_ metadata: PageMetadata, to siteID: UUID) {
        guard let index = sites.firstIndex(where: { $0.id == siteID }) else { return }
        if let color = metadata.themeColor, sites[index].themeColor != color {
            sites[index].themeColor = color
        }
        guard !metadata.iconURLs.isEmpty else { return }
        IconFetcher.download(candidates: metadata.iconURLs, for: siteID) { [weak self] saved in
            if saved { self?.iconVersion += 1 }
        }
    }

    /// Removes cookies, caches and storage that belong to the site's domain.
    func clearData(for site: Site, completion: @escaping () -> Void) {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            let matching = records.filter { site.matchesDataRecord(named: $0.displayName) }
            store.removeData(ofTypes: types, for: matching) {
                DispatchQueue.main.async { completion() }
            }
        }
    }

    private func fetchMetadata(for site: Site) {
        IconFetcher.fetch(for: site) { [weak self] metadata in
            guard let self, let metadata else { return }
            self.apply(metadata, to: site.id)
        }
    }

    private func refreshMissingIcons() {
        for site in sites where IconStore.image(for: site.id) == nil {
            fetchMetadata(for: site)
        }
    }

    private func save() {
        SharedSites.save(sites, to: .standard)
        SharedSites.save(sites, to: AppGroup.defaults)
        DeepLinkRouter.updateQuickActions(with: sites)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
