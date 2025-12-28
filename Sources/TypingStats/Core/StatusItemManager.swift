import Cocoa
import SwiftUI
import Combine

/// Manages the NSStatusItem with custom SwiftUI content (icon + text)
final class StatusItemManager: ObservableObject {
    private var hostingView: NSHostingView<StatusItemView>?
    private(set) var statusItem: NSStatusItem?
    private var sizePassthrough = PassthroughSubject<CGSize, Never>()
    private var sizeCancellable: AnyCancellable?
    private var clickHandler: (() -> Void)?

    @Published var keystrokeCount: Int = 0
    @Published var displayText: String? = nil

    func createStatusItem(onClick: @escaping () -> Void) {
        self.clickHandler = onClick

        // Create status item
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Create SwiftUI view wrapped in NSHostingView
        let rootView = StatusItemView(
            sizePassthrough: sizePassthrough,
            count: keystrokeCount,
            displayText: displayText
        )
        let hostingView = NSHostingView(rootView: rootView)

        // Initial frame - will be updated dynamically
        hostingView.frame = NSRect(x: 0, y: 0, width: 60, height: 22)

        if let button = statusItem.button {
            button.frame = hostingView.frame
            button.addSubview(hostingView)

            // Set up click action
            button.target = self
            button.action = #selector(statusItemClicked)
        }

        self.statusItem = statusItem
        self.hostingView = hostingView

        // Listen for size changes from the SwiftUI view
        sizeCancellable = sizePassthrough.sink { [weak self] size in
            let frame = NSRect(origin: .zero, size: CGSize(width: size.width + 8, height: 22))
            self?.hostingView?.frame = frame
            self?.statusItem?.button?.frame = frame
        }
    }

    @objc private func statusItemClicked() {
        clickHandler?()
    }

    func updateCount(_ count: Int) {
        keystrokeCount = count
        displayText = nil

        // Update SwiftUI view
        let rootView = StatusItemView(
            sizePassthrough: sizePassthrough,
            count: count,
            displayText: nil
        )
        hostingView?.rootView = rootView
    }

    func updateText(_ text: String) {
        displayText = text

        // Update SwiftUI view
        let rootView = StatusItemView(
            sizePassthrough: sizePassthrough,
            count: keystrokeCount,
            displayText: text
        )
        hostingView?.rootView = rootView
    }

    func showPopover(_ popover: NSPopover) {
        guard let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

// MARK: - Size Preference Key
private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

// MARK: - Status Item SwiftUI View
struct StatusItemView: View {
    var sizePassthrough: PassthroughSubject<CGSize, Never>
    var count: Int
    var displayText: String?

    private var formattedCount: String {
        if count >= 1000 {
            let k = Double(count) / 1000.0
            return String(format: "%.1fk", k)
        }
        return "\(count)"
    }

    private var displayValue: String {
        displayText ?? formattedCount
    }

    private var iconName: String {
        displayText != nil ? "mouse" : "keyboard"
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .font(.system(size: 14))
            Text(displayValue)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
        }
        .foregroundColor(.primary)
        .fixedSize()
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geometry.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self) { size in
            sizePassthrough.send(size)
        }
    }
}
