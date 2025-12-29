import SwiftUI

struct SettingsView: View {
    @ObservedObject var appSettings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Menu Bar Display
            VStack(alignment: .leading, spacing: 8) {
                Text("Menu Bar Display")
                    .font(.headline)
                Text("What to show in menu bar icon")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(Metric.allCases, id: \.self) { metric in
                    Button(action: {
                        appSettings.toggleMetric(metric)
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: appSettings.selectedMetrics.contains(metric) ? "checkmark.square.fill" : "square")
                                .frame(width: 16)
                            Image(systemName: metric.iconName)
                                .frame(width: 16)
                            Text(metric.displayName)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // Mouse DPI
            VStack(alignment: .leading, spacing: 8) {
                Text("Mouse DPI")
                    .font(.headline)
                Text("For accurate distance calculation (default: 96)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("DPI", value: $appSettings.dpi, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }

            // Distance Format
            VStack(alignment: .leading, spacing: 8) {
                Text("Distance Format")
                    .font(.headline)
                Text("How to display mouse distance in history")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Distance Format", selection: $appSettings.distanceFormat) {
                    ForEach(DistanceFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            Spacer()

            Text("Changes apply automatically")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(20)
        .frame(width: 320, height: 380, alignment: .topLeading)
    }
}

final class SettingsWindowController {
    private var window: NSWindow?
    private var hostingController: NSHostingController<SettingsView>?
    private var closeObserver: NSObjectProtocol?

    deinit {
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func show(appSettings: AppSettings) {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(appSettings: appSettings)
        let hosting = NSHostingController(rootView: settingsView)
        hostingController = hosting

        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "Settings"
        newWindow.styleMask = [.titled, .closable]
        newWindow.setContentSize(NSSize(width: 320, height: 380))

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = newWindow.frame
            let x = (screenFrame.width - windowFrame.width) / 2 + screenFrame.origin.x
            let y = (screenFrame.height - windowFrame.height) / 2 + screenFrame.origin.y
            newWindow.setFrameOrigin(NSPoint(x: x, y: y))
        }

        newWindow.isReleasedWhenClosed = false

        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { [weak self] _ in
            self?.window = nil
            self?.hostingController = nil
        }

        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
            closeObserver = nil
        }
        window?.close()
        window = nil
        hostingController = nil
    }
}
