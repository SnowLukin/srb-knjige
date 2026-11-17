import SwiftUI
import AppKit
import KnjigeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Приложение собирается через Swift Package Manager без Info.plist —
        // без этого окно не получает фокус и нет иконки в Доке.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct KnjigeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup("Knjige — книги предузетника") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1200, height: 800)
        // Окно нельзя сделать меньше минимального размера интерфейса — иначе содержимое уезжает за край.
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Данные") {
                Button("Открыть папку с данными") {
                    NSWorkspace.shared.open(store.repository.baseURL)
                }
                Button("Загрузить недостающие курсы НБС") {
                    Task { _ = await store.fetchMissingRates() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
