import SwiftUI
import CoreText
import MoonlitCore

@main
struct MoonlitMacApp: App {
    @StateObject private var profileManager = ProfileManager.shared
    @StateObject private var roleManager = RoleManager.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MacContentView()
                .environmentObject(profileManager)
                .environmentObject(roleManager)
                .frame(minWidth: 900, minHeight: 600)
                .background(MoonlitTheme.background)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)

        WindowGroup(id: "player", for: PlayerLaunch.self) { $launch in
            if let launch = launch {
                MacPlayerView(launch: launch)
                    .environmentObject(profileManager)
                    .frame(minWidth: 900, minHeight: 550)
                    .background(Color.black)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 700)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        registerFonts()
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first else { return }
            window.identifier = NSUserInterfaceItemIdentifier("moonlit-main")
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.backgroundColor = NSColor(
                red: 0.051, green: 0.051, blue: 0.051, alpha: 1.0
            )
        }
    }

    private func registerFonts() {
        guard let url = Bundle.main.url(forResource: "Montserrat-ExtraBold", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}
