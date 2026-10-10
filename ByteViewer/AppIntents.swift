import AppIntents
import Foundation

/// A saved site, as seen by the Shortcuts app and Siri.
struct SiteEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Site"
    static var defaultQuery = SiteQuery()

    var id: String
    var name: String
    var host: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(host)")
    }

    init(site: Site) {
        id = site.id.uuidString
        name = site.displayName
        host = site.host ?? ""
    }
}

struct SiteQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SiteEntity] {
        SharedSites.load()
            .filter { identifiers.contains($0.id.uuidString) }
            .map { SiteEntity(site: $0) }
    }

    func suggestedEntities() async throws -> [SiteEntity] {
        SharedSites.load().map { SiteEntity(site: $0) }
    }
}

/// "Open Site" action. A shortcut made from it can be added to the Home Screen with its own icon.
struct OpenSiteIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Site"
    static var description = IntentDescription("Opens a saved site full screen in ByteViewer.")
    static var openAppWhenRun = true

    @Parameter(title: "Site")
    var site: SiteEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$site)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: site.id) {
            DeepLinkRouter.shared.request = .site(id)
        }
        return .result()
    }
}

struct ByteViewerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenSiteIntent(),
            phrases: ["Open a site in \(.applicationName)"]
        )
    }
}
