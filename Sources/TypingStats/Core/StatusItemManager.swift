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
    @Published var wordCount: Int = 0
    @Published var clickCount: Int = 0
    @Published var distanceText: String? = nil
    @Published var displayMode: String = "keystrokes"

    func createStatusItem(onClick: @escaping () -> Void) {
        self.clickHandler = onClick

        // Create status item
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Create SwiftUI view wrapped in NSHostingView
        let rootView = StatusItemView(
            sizePassthrough: sizePassthrough,
            keystrokeCount: keystrokeCount,
            wordCount: wordCount,
            clickCount: clickCount,
            distanceText: distanceText,
            displayMode: displayMode
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
        updateStatusView()
    }

    func updateWordCount(_ count: Int) {
        wordCount = count
        updateStatusView()
    }

    func updateClickCount(_ count: Int) {
        clickCount = count
        updateStatusView()
    }

    func updateDistanceText(_ text: String?) {
        distanceText = text
        updateStatusView()
    }

    func updateDisplayMode(_ mode: String) {
        displayMode = mode
        updateStatusView()
    }

    private func updateStatusView() {
        let rootView = StatusItemView(
            sizePassthrough: sizePassthrough,
            keystrokeCount: keystrokeCount,
            wordCount: wordCount,
            clickCount: clickCount,
            distanceText: distanceText,
            displayMode: displayMode
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
    var keystrokeCount: Int
    var wordCount: Int
    var clickCount: Int
    var distanceText: String?
    var displayMode: String

    private func formatCount(_ count: Int) -> String {
        if count >= 1000000 {
            let m = Double(count) / 1000000.0
            return String(format: "%.1fM", m)
        } else if count >= 1000 {
            let k = Double(count) / 1000.0
            return String(format: "%.1fk", k)
        }
        return "\(count)"
    }

    private var displayText: String {
        switch displayMode {
        case "all":
            var parts: [String] = []
            if keystrokeCount > 0 {
                parts.append(formatCount(keystrokeCount))
            }
            if clickCount > 0 {
                parts.append(formatCount(clickCount))
            }
            if let distance = distanceText {
                parts.append(distance)
            }
            return parts.joined(separator: " / ")
        case "keystrokes":
            return formatCount(keystrokeCount)
        case "words":
            return formatCount(wordCount)
        case "clicks":
            return formatCount(clickCount)
        case "distance":
            return distanceText ?? "0 mi"
        default:
            return formatCount(keystrokeCount)
        }
    }

    private var iconName: String {
        switch displayMode {
        case "distance":
            return "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left"
        case "clicks":
            return "cursorarrow.click"
        case "words", "all":
            return "text.alignleft"
        default:
            return "keyboard"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .font(.system(size: 14))
            Text(displayText)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .lineLimit(1)
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
