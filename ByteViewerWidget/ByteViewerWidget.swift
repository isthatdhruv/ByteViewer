import SwiftUI
import WidgetKit

struct SiteEntry: TimelineEntry {
    let date: Date
    let sites: [Site]
}

struct SitesProvider: TimelineProvider {
    static let samples: [Site] = ["Docs", "Mail", "News", "Chat"].map {
        Site(name: $0, url: "https://\($0.lowercased()).example.com")
    }

    func placeholder(in context: Context) -> SiteEntry {
        SiteEntry(date: Date(), sites: Self.samples)
    }

    func getSnapshot(in context: Context, completion: @escaping (SiteEntry) -> Void) {
        let sites = SharedSites.load()
        completion(SiteEntry(date: Date(), sites: sites.isEmpty ? Self.samples : sites))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SiteEntry>) -> Void) {
        // The app reloads the timeline whenever the site list changes.
        completion(Timeline(entries: [SiteEntry(date: Date(), sites: SharedSites.load())], policy: .never))
    }
}

struct SitesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SiteEntry

    private var capacity: Int {
        switch family {
        case .systemSmall: return 1
        case .systemMedium: return 4
        default: return 8
        }
    }

    private var iconSize: CGFloat {
        family == .systemLarge ? 52 : 40
    }

    var body: some View {
        Group {
            if entry.sites.isEmpty {
                emptyView
            } else if family == .systemSmall, let first = entry.sites.first {
                tile(first, iconSize: 60)
                    .widgetURL(first.deepLink)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 14) {
                    ForEach(entry.sites.prefix(capacity)) { site in
                        Link(destination: site.deepLink) {
                            tile(site, iconSize: iconSize)
                        }
                    }
                }
                .padding(8)
            }
        }
        .widgetBackground()
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "globe")
                .font(.title)
            Text("Add sites in ByteViewer")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding()
    }

    private func tile(_ site: Site, iconSize: CGFloat) -> some View {
        VStack(spacing: 6) {
            icon(for: site, size: iconSize)
            Text(site.displayName)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private func icon(for site: Site, size: CGFloat) -> some View {
        Group {
            if let image = IconStore.image(for: site.id) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    ThemeColor.color(from: site.themeColor) ?? Color(red: 0.2, green: 0.21, blue: 0.24)
                    Image(systemName: "globe")
                        .font(.system(size: size * 0.5, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

extension View {
    /// iOS 17 widgets must declare their background through `containerBackground`.
    @ViewBuilder
    func widgetBackground() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget) { Color(.systemBackground) }
        } else {
            background(Color(.systemBackground))
        }
    }
}

struct SitesWidget: Widget {
    let kind = "ByteViewerSites"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SitesProvider()) { entry in
            SitesWidgetView(entry: entry)
        }
        .configurationDisplayName("Sites")
        .description("Open your saved sites with one tap.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct ByteViewerWidgetBundle: WidgetBundle {
    var body: some Widget {
        SitesWidget()
    }
}
