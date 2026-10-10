import SwiftUI

/// Full-screen presentation of a single site: no browser chrome, just the page
/// and a small floating menu button.
struct SiteView: View {
    let site: Site

    @EnvironmentObject private var store: SiteStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = WebViewModel()
    @State private var controlsVisible: Bool
    @State private var orientation: OrientationMode
    @State private var hideStatusBar: Bool
    @State private var isLocked: Bool
    @State private var authInProgress = false
    @State private var authFailed = false
    @State private var themeColor: UIColor?
    @State private var showingLauncher = false

    init(site: Site) {
        self.site = site
        _controlsVisible = State(initialValue: !site.kioskMode)
        _orientation = State(initialValue: site.orientation)
        _hideStatusBar = State(initialValue: site.hideStatusBar || site.kioskMode)
        _isLocked = State(initialValue: site.requiresAuth)
        _themeColor = State(initialValue: ThemeColor.uiColor(from: site.themeColor))
    }

    private var isSaved: Bool { store.site(id: site.id) != nil }

    /// Light or dark status bar text to suit the site's theme colour.
    private var colorScheme: ColorScheme? {
        guard let themeColor else { return nil }
        return ThemeColor.isDark(themeColor) ? .dark : .light
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            (themeColor.map { Color(uiColor: $0) } ?? Color(.systemBackground))
                .ignoresSafeArea()

            if site.resolvedURL != nil {
                WebView(site: site, model: model, onShowControls: revealControls, onMetadata: handleMetadata)
                    .ignoresSafeArea()   // the page gets the whole screen; WebKit handles the safe areas
            } else {
                errorView("That address is not a valid URL.")
            }

            if model.isLoading && !isLocked {
                VStack {
                    ProgressView(value: model.progress)
                        .progressViewStyle(.linear)
                    Spacer()
                }
            }

            if let message = model.errorMessage, !isLocked {
                errorView(message)
            }

            if isLocked {
                lockView
            } else if controlsVisible {
                menuButton
            }
        }
        .preferredColorScheme(colorScheme)
        .statusBarHidden(hideStatusBar)
        .persistentSystemOverlays(hideStatusBar ? .hidden : .automatic)
        .sheet(isPresented: $showingLauncher) {
            LauncherSheet(site: site)
                .environmentObject(store)
        }
        .onAppear {
            OrientationController.apply(orientation)
            UIApplication.shared.isIdleTimerDisabled = site.keepAwake
            if isLocked { unlock() }
        }
        .onDisappear {
            OrientationController.apply(.auto)
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: orientation) { newValue in OrientationController.apply(newValue) }
        .onChange(of: scenePhase) { phase in
            guard site.requiresAuth else { return }
            if phase == .background {
                isLocked = true
            } else if phase == .active, isLocked, !authInProgress {
                unlock()
            }
        }
    }

    // MARK: - Pieces

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

            if let url = model.currentURL ?? site.resolvedURL {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Button {
                    openURL(url)
                } label: {
                    Label("Open in Safari", systemImage: "safari")
                }
            }

            if isSaved {
                Button {
                    showingLauncher = true
                } label: {
                    Label("Add to Home Screen", systemImage: "plus.app")
                }
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

    private var lockView: some View {
        VStack(spacing: 16) {
            SiteIconView(site: site, size: 72, version: store.iconVersion)
            Text(site.displayName)
                .font(.title2.weight(.semibold))
            Text(authFailed ? "Authentication failed." : "Locked")
                .foregroundStyle(.secondary)
            HStack {
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Unlock") { unlock() }
                    .buttonStyle(.borderedProminent)
                    .disabled(authInProgress)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .ignoresSafeArea()
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

    // MARK: - Actions

    private func unlock() {
        authInProgress = true
        Authenticator.authenticate(reason: "Unlock \(site.displayName)") { success in
            authInProgress = false
            authFailed = !success
            if success { isLocked = false }
        }
    }

    /// Three-finger tap. In kiosk mode the controls only come back after device authentication.
    private func revealControls() {
        if site.kioskMode && Authenticator.isAvailable {
            Authenticator.authenticate(reason: "Show the controls") { success in
                if success { withAnimation { controlsVisible = true } }
            }
        } else {
            withAnimation { controlsVisible = true }
        }
    }

    private func handleMetadata(_ metadata: PageMetadata) {
        if let color = ThemeColor.uiColor(from: metadata.themeColor) {
            themeColor = color
        }
        store.apply(metadata, to: site.id)
    }
}
