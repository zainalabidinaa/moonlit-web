import SwiftUI
import LunaCore

@main
struct LunaMacApp: App {
    @StateObject private var profileManager = ProfileManager.shared
    @StateObject private var roleManager = RoleManager.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MacContentView()
                .environmentObject(profileManager)
                .environmentObject(roleManager)
                .frame(minWidth: 900, minHeight: 600)
                .background(LunaTheme.background)
                .onAppear {
                    configureWindow()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
    }

    private func configureWindow() {
        guard let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == "luna-main" || $0.identifier == nil
        }) else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(
            red: 0.05, green: 0.05, blue: 0.12, alpha: 1.0
        )
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApp.windows.first {
            window.identifier = NSUserInterfaceItemIdentifier("luna-main")
        }
    }
}
