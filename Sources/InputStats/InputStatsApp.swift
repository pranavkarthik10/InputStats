import SwiftUI
import Combine
import ServiceManagement

@main
struct InputStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemManager: StatusItemManager!
    private var repository: StatsRepository!
    private var permissionManager: PermissionManager!
    private var appSettings: AppSettings!
    private var historyWindowController = HistoryWindowController()
    private var settingsWindowController = SettingsWindowController()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize managers
        repository = StatsRepository()
        permissionManager = PermissionManager()
        appSettings = AppSettings()
        statusItemManager = StatusItemManager()

        // Create status item with click handler
        statusItemManager.createStatusItem { [weak self] in
            self?.showMenu()
        }

        // Update status item when stats or settings change
        repository.$todayStats
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)

        appSettings.$selectedMetrics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)

        // Start monitoring if already authorized
        permissionManager.$isAuthorized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authorized in
                if authorized {
                    self?.repository.setupKeystrokeMonitoring()
                    self?.repository.setupMouseMonitoring()
                }
            }
            .store(in: &cancellables)

        // Hide dock icon (menubar-only app)
        NSApp.setActivationPolicy(.accessory)
    }

    private func updateStatusItem() {
        let todayStats = repository.todayStats

        statusItemManager.updateCount(Int(todayStats?.totalKeystrokes ?? 0))
        statusItemManager.updateWordCount(Int(todayStats?.totalWords ?? 0))
        statusItemManager.updateClickCount(Int(todayStats?.totalMouseClicks ?? 0))

        let pixels = todayStats?.totalMouseDistance ?? 0
        statusItemManager.updateDistanceText(appSettings.formatDistance(pixels))

        statusItemManager.updateSelectedMetrics(appSettings.selectedMetrics)
    }

    private func showMenu() {
        guard let button = statusItemManager.statusItem?.button else { return }

        let menu = NSMenu()

        // Check if we have permission
        if permissionManager.isAuthorized {
            // Keyboard Stats
            menu.addItem(NSMenuItem.separator())
            let keyboardHeader = NSMenuItem(title: "Keyboard", action: nil, keyEquivalent: "")
            keyboardHeader.isEnabled = false
            menu.addItem(keyboardHeader)

            let todayKeysItem = NSMenuItem(title: "  Today: \(formatNumber(repository.todayStats?.totalKeystrokes ?? 0)) keys", action: nil, keyEquivalent: "")
            todayKeysItem.isEnabled = false
            menu.addItem(todayKeysItem)

            let todayWordsItem = NSMenuItem(title: "  Today: \(formatNumber(repository.todayStats?.totalWords ?? 0)) words", action: nil, keyEquivalent: "")
            todayWordsItem.isEnabled = false
            menu.addItem(todayWordsItem)

            let yesterdayKeysItem = NSMenuItem(title: "  Yesterday: \(formatNumber(repository.yesterdayCount)) keys", action: nil, keyEquivalent: "")
            yesterdayKeysItem.isEnabled = false
            menu.addItem(yesterdayKeysItem)

            let yesterdayWordsItem = NSMenuItem(title: "  Yesterday: \(formatNumber(repository.yesterdayWords)) words", action: nil, keyEquivalent: "")
            yesterdayWordsItem.isEnabled = false
            menu.addItem(yesterdayWordsItem)

            // Mouse Stats
            menu.addItem(NSMenuItem.separator())
            let mouseHeader = NSMenuItem(title: "Mouse", action: nil, keyEquivalent: "")
            mouseHeader.isEnabled = false
            menu.addItem(mouseHeader)

            let todayClicksItem = NSMenuItem(title: "  Today: \(formatNumber(repository.todayStats?.totalMouseClicks ?? 0)) clicks", action: nil, keyEquivalent: "")
            todayClicksItem.isEnabled = false
            menu.addItem(todayClicksItem)

            let todayScrollsItem = NSMenuItem(title: "  Today: \(formatNumber(repository.todayStats?.totalMouseScroll ?? 0)) scrolls", action: nil, keyEquivalent: "")
            todayScrollsItem.isEnabled = false
            menu.addItem(todayScrollsItem)

            let todayDistance = repository.todayStats?.totalMouseDistance ?? 0
            let todayDistanceItem = NSMenuItem(title: "  Today: \(appSettings.formatDistance(todayDistance))", action: nil, keyEquivalent: "")
            todayDistanceItem.isEnabled = false
            menu.addItem(todayDistanceItem)

            let yesterdayClicksItem = NSMenuItem(title: "  Yesterday: \(formatNumber(repository.yesterdayClicks)) clicks", action: nil, keyEquivalent: "")
            yesterdayClicksItem.isEnabled = false
            menu.addItem(yesterdayClicksItem)

            let yesterdayScrollsItem = NSMenuItem(title: "  Yesterday: \(formatNumber(repository.yesterdayScrolls)) scrolls", action: nil, keyEquivalent: "")
            yesterdayScrollsItem.isEnabled = false
            menu.addItem(yesterdayScrollsItem)

            let yesterdayDistanceItem = NSMenuItem(title: "  Yesterday: \(appSettings.formatDistance(repository.yesterdayDistance))", action: nil, keyEquivalent: "")
            yesterdayDistanceItem.isEnabled = false
            menu.addItem(yesterdayDistanceItem)
        } else {
            let permItem = NSMenuItem(title: "Permission Required", action: #selector(grantPermission), keyEquivalent: "")
            permItem.target = self
            menu.addItem(permItem)
        }

        menu.addItem(NSMenuItem.separator())

        // View History
        let historyItem = NSMenuItem(title: "View History...", action: #selector(viewHistory), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)

        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Start at Login
        let loginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleStartAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isStartAtLoginEnabled() ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // Show menu
        statusItemManager.statusItem?.menu = menu
        button.performClick(nil)
        statusItemManager.statusItem?.menu = nil
    }

    private func formatNumber(_ number: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    @objc private func grantPermission() {
        permissionManager.requestAuthorization()
    }

    @objc private func viewHistory() {
        historyWindowController.show(stats: repository.getAllStats(), appSettings: appSettings)
    }

    @objc private func openSettings() {
        settingsWindowController.show(appSettings: appSettings)
    }

    @objc private func toggleStartAtLogin() {
        let newValue = !isStartAtLoginEnabled()
        setStartAtLogin(enabled: newValue)
    }

    private func isStartAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    private func setStartAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Login item registration failed - user can retry
            }
        }
    }

    @objc private func quit() {
        repository.forceSave()
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        repository.forceSave()
    }
}
