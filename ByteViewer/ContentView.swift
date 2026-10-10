import SwiftUI

struct ContentView: View {
    @StateObject private var store = SiteStore()
    @ObservedObject private var router = DeepLinkRouter.shared
    @State private var quickURL = ""
    @State private var openSite: Site?
    @State private var editingSite: Site?
    @State private var launcherSite: Site?
    @State private var showingAdd = false
    @State private var didAutoOpen = false

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        NavigationStack {
            List {
                Section("Open a website") {
                    HStack {
                        TextField("example.com", text: $quickURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit(openQuick)
                        Button(action: openQuick) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title2)
                        }
                        .disabled(Site.normalize(quickURL, allowHTTP: true) == nil)
                    }
                }

                Section {
                    if store.sites.isEmpty {
                        Text("No saved sites yet. Tap + to add one.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.sites) { site in
                        let isDefault = store.autoOpenSiteID == site.id.uuidString
                        Button {
                            openSite = site
                        } label: {
                            SiteRow(site: site, isDefault: isDefault, iconVersion: store.iconVersion)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.remove(site)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                editingSite = site
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                toggleDefault(site)
                            } label: {
                                Label(isDefault ? "Unset" : "Default", systemImage: isDefault ? "star.slash" : "star")
                            }
                            .tint(.yellow)
                            Button {
                                launcherSite = site
                            } label: {
                                Label("Home Screen", systemImage: "plus.app")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button {
                                editingSite = site
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button {
                                launcherSite = site
                            } label: {
                                Label("Add to Home Screen", systemImage: "plus.app")
                            }
                            Button {
                                toggleDefault(site)
                            } label: {
                                Label(isDefault ? "Do not open at launch" : "Open at launch", systemImage: "star")
                            }
                            Button(role: .destructive) {
                                store.remove(site)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onMove(perform: store.move)
                } header: {
                    Text("My sites")
                } footer: {
                    Text("Swipe right on a site to open it at launch or put it on the Home Screen. The first four sites also appear when you long-press the app icon and in the widget.")
                }

                Section {
                    BrandRow()
                }
            }
            .navigationTitle("ByteViewer")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                SiteEditor(site: Site(name: "", url: "", desktopMode: isPad), title: "Add site", isNew: true) {
                    store.add($0)
                }
                .environmentObject(store)
            }
            .sheet(item: $editingSite) { site in
                SiteEditor(site: site, title: "Edit site") { store.update($0) }
                    .environmentObject(store)
            }
            .sheet(item: $launcherSite) { site in
                LauncherSheet(site: site)
                    .environmentObject(store)
            }
            .fullScreenCover(item: $openSite) { site in
                SiteView(site: site)
                    .environmentObject(store)
            }
            .onAppear(perform: autoOpenIfNeeded)
            .onReceive(router.$request) { request in
                if let request { handle(request) }
            }
        }
    }

    private func openQuick() {
        guard Site.normalize(quickURL, allowHTTP: true) != nil else { return }
        var site = Site(name: "", url: quickURL, desktopMode: isPad)
        site.allowHTTP = quickURL.lowercased().hasPrefix("http://")
        openSite = site
    }

    private func toggleDefault(_ site: Site) {
        store.autoOpenSiteID = store.autoOpenSiteID == site.id.uuidString ? "" : site.id.uuidString
    }

    private func autoOpenIfNeeded() {
        guard !didAutoOpen else { return }
        didAutoOpen = true
        // A launch through a URL, Quick Action or the widget wins over the default site.
        guard router.request == nil, let site = store.autoOpenSite else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if openSite == nil { openSite = site }
        }
    }

    /// Opens whatever a `byteviewer://` link, Quick Action, widget tap or Shortcut asked for.
    private func handle(_ request: DeepLinkRequest) {
        DispatchQueue.main.async { router.request = nil }
        let target: Site?
        switch request {
        case .site(let id):
            target = store.site(id: id)
        case .url(let url):
            var site = Site(name: "", url: url.absoluteString, desktopMode: isPad)
            site.allowHTTP = true
            target = site
        }
        guard let target else { return }
        didAutoOpen = true
        if openSite != nil {
            openSite = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { openSite = target }
        } else {
            openSite = target
        }
    }
}

/// ByteKnot Labs branding: mark, wordmark, version and a link to the project.
private struct BrandRow: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                (Text("Byte").foregroundColor(.primary) + Text("Viewer").foregroundColor(.secondary))
                    .font(.headline.weight(.bold))
                Text("by ByteKnot Labs  ·  v\(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let url = URL(string: "https://github.com/isthatdhruv/ByteViewer") {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// The site's cached icon, or a globe on the site's theme colour.
struct SiteIconView: View {
    let site: Site
    var size: CGFloat = 32
    var version: Int = 0

    var body: some View {
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
        .id(version)
    }
}

private struct SiteRow: View {
    let site: Site
    let isDefault: Bool
    let iconVersion: Int

    var body: some View {
        HStack(spacing: 12) {
            SiteIconView(site: site, size: 36, version: iconVersion)
            VStack(alignment: .leading, spacing: 2) {
                Text(site.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(site.resolvedURL?.absoluteString ?? site.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isDefault {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }
            if site.requiresAuth {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
            }
            if site.desktopMode {
                Image(systemName: "desktopcomputer")
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct SiteEditor: View {
    @EnvironmentObject private var store: SiteStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Site
    @State private var confirmClear = false
    @State private var showClearedNotice = false
    let title: String
    let isNew: Bool
    let onSave: (Site) -> Void

    init(site: Site, title: String, isNew: Bool = false, onSave: @escaping (Site) -> Void) {
        _draft = State(initialValue: site)
        self.title = title
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Website") {
                    TextField("Name (optional)", text: $draft.name)
                    TextField("https://example.com", text: $draft.url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Toggle("Request desktop site", isOn: $draft.desktopMode)
                    Toggle("Hide status bar", isOn: $draft.hideStatusBar)
                    Toggle("Edge to edge (viewport-fit=cover)", isOn: $draft.edgeToEdge)
                    Picker("Rotation", selection: $draft.orientation) {
                        ForEach(OrientationMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                } header: {
                    Text("Display")
                } footer: {
                    Text("Edge to edge makes the page draw under the notch and home indicator. Leave it off unless the site handles safe areas itself.")
                }

                Section {
                    Toggle("Stay in this site", isOn: $draft.stayInSite)
                    Toggle("Keep screen awake", isOn: $draft.keepAwake)
                    Toggle("Kiosk mode", isOn: $draft.kioskMode)
                } header: {
                    Text("Behaviour")
                } footer: {
                    Text("Stay in this site sends links to other websites to Safari. Kiosk mode hides the controls, the status bar and swipe navigation; a three-finger tap plus Face ID or passcode brings the controls back.")
                }

                Section {
                    Toggle("Require Face ID / passcode", isOn: $draft.requiresAuth)
                    Toggle("Private mode", isOn: $draft.privateMode)
                    Toggle("Allow plain http://", isOn: $draft.allowHTTP)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Private mode keeps no cookies or logins between visits. Plain http:// pages are not encrypted; use it only for local or trusted networks.")
                }

                if !isNew {
                    Section {
                        Button("Clear cookies and site data", role: .destructive) {
                            confirmClear = true
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.resolvedURL == nil)
                }
            }
            .confirmationDialog("Clear all cookies, logins and cached data for \(draft.displayName)?",
                                isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear site data", role: .destructive) {
                    store.clearData(for: draft) { showClearedNotice = true }
                }
            }
            .alert("Site data cleared", isPresented: $showClearedNotice) {
                Button("OK") {}
            }
        }
    }
}
