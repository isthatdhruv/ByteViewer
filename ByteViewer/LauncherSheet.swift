import SwiftUI

/// Explains how to put a site on the Home Screen with its own icon, via the Shortcuts app.
struct LauncherSheet: View {
    let site: Site

    @EnvironmentObject private var store: SiteStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        SiteIconView(site: site, size: 44, version: store.iconVersion)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(site.displayName)
                                .font(.headline)
                            Text(site.host ?? site.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Launcher link") {
                    Text(site.deepLink.absoluteString)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = site.deepLink.absoluteString
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }

                Section("Put it on the Home Screen") {
                    step(1, "Open the Shortcuts app and tap + to make a new shortcut.")
                    step(2, "Add the action “Open URL” and paste the link above, or add ByteViewer’s “Open Site” action and pick \(site.displayName).")
                    step(3, "Tap the share button, choose “Add to Home Screen”, pick an icon and a name, then tap Add.")
                    Button {
                        if let url = URL(string: "shortcuts://create-shortcut") { openURL(url) }
                    } label: {
                        Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                    }
                }

                Section {
                    Text("You can also say “Hey Siri, open a site in ByteViewer”, long-press the ByteViewer icon for your first four sites, or add the ByteViewer widget.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Home Screen launcher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
                .foregroundStyle(.white)
            Text(text)
        }
    }
}
