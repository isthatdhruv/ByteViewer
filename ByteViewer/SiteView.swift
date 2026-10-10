import SwiftUI

/// Full-screen presentation of a single site: no browser chrome, just the page
/// and a small floating menu button.
struct SiteView: View {
    let site: Site

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var model = WebViewModel()
    @State private var controlsVisible = true
    @State private var orientation: OrientationMode
    @State private var hideStatusBar: Bool

    init(site: Site) {
        self.site = site
        _orientation = State(initialValue: site.orientation)
        _hideStatusBar = State(initialValue: site.hideStatusBar)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(.systemBackground).ignoresSafeArea()

            if let url = site.resolvedURL {
                WebView(url: url, desktopMode: site.desktopMode, edgeToEdge: site.edgeToEdge, model: model) {
                    withAnimation { controlsVisible = true }
                }
                .ignoresSafeArea()   // the page gets the whole screen; WebKit handles the safe areas
            } else {
                errorView("That address is not a valid URL.")
            }

            if model.isLoading {
                VStack {
                    ProgressView(value: model.progress)
                        .progressViewStyle(.linear)
                    Spacer()
                }
            }

            if let message = model.errorMessage {
                errorView(message)
            }

            if controlsVisible {
                menuButton
            }
        }
        .statusBarHidden(hideStatusBar)
        .persistentSystemOverlays(hideStatusBar ? .hidden : .automatic)
        .onAppear { OrientationController.apply(orientation) }
        .onDisappear { OrientationController.apply(.auto) }
        .onChange(of: orientation) { newValue in OrientationController.apply(newValue) }
    }

    private var menuButton: some View {
        Menu {
            Button(action: model.goBack) { Label("Back", systemImage: "chevron.left") }
                .disabled(!model.canGoBack)
            Button(action: model.goForward) { Label("Forward", systemImage: "chevron.right") }
                .disabled(!model.canGoForward)
            Button(action: model.reload) { Label("Reload", systemImage: "arrow.clockwise") }

            Divider()

            Picker("Rotation", selection: $orientation) {
                ForEach(OrientationMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Toggle(isOn: $hideStatusBar) {
                Label("Hide status bar", systemImage: "rectangle.topthird.inset.filled")
            }

            Divider()

            Button {
                if let url = model.currentURL ?? site.resolvedURL { openURL(url) }
            } label: {
                Label("Open in Safari", systemImage: "safari")
            }

            Button {
                withAnimation { controlsVisible = false }
            } label: {
                Label("Hide controls (3-finger tap to show)", systemImage: "eye.slash")
            }

            Divider()

            Button(role: .destructive) {
                dismiss()
            } label: {
                Label("Close site", systemImage: "xmark.circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 34))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.45))
                .shadow(radius: 3)
                .padding(16)
        }
        .opacity(0.75)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack {
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Retry") {
                    if let url = model.currentURL ?? site.resolvedURL { model.load(url) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .ignoresSafeArea()
    }
}
