import SwiftUI

struct ContentView: View {
    @StateObject private var store = SiteStore()
    @State private var quickURL = ""
    @State private var openSite: Site?
    @State private var editingSite: Site?
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
                        .disabled(Site.normalize(quickURL) == nil)
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
                            SiteRow(site: site, isDefault: isDefault)
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
                        }
                        .contextMenu {
                            Button {
                                editingSite = site
                            } label: {
                                Label("Edit", systemImage: "pencil")
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
                    Text("Swipe right on a site to open it automatically at launch. Inside a site, use the ••• button, or tap with three fingers if you hid it.")
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
                SiteEditor(site: Site(name: "", url: "", desktopMode: isPad), title: "Add site") { store.add($0) }
            }
            .sheet(item: $editingSite) { site in
                SiteEditor(site: site, title: "Edit site") { store.update($0) }
            }
            .fullScreenCover(item: $openSite) { site in
                SiteView(site: site)
            }
            .onAppear(perform: autoOpenIfNeeded)
        }
    }

    private func openQuick() {
        guard Site.normalize(quickURL) != nil else { return }
        openSite = Site(name: "", url: quickURL, desktopMode: isPad)
    }

    private func toggleDefault(_ site: Site) {
        store.autoOpenSiteID = store.autoOpenSiteID == site.id.uuidString ? "" : site.id.uuidString
    }

    private func autoOpenIfNeeded() {
        guard !didAutoOpen else { return }
        didAutoOpen = true
        guard let site = store.autoOpenSite else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            openSite = site
        }
    }
}

private struct SiteRow: View {
    let site: Site
    let isDefault: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
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
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Site
    let title: String
    let onSave: (Site) -> Void

    init(site: Site, title: String, onSave: @escaping (Site) -> Void) {
        _draft = State(initialValue: site)
        self.title = title
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
        }
    }
}
