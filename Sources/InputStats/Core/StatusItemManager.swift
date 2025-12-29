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
    @Published var selectedMetrics: Set<Metric> = [.keystrokes]

    func createStatusItem(onClick: @escaping () -> Void) {
        self.clickHandler = onClick

        // Create status item with variable length
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Create SwiftUI view wrapped in NSHostingView
        let rootView = StatusItemView(
            sizePassthrough: sizePassthrough,
            keystrokeCount: keystrokeCount,
            wordCount: wordCount,
            clickCount: clickCount,
            distanceText: distanceText,
            selectedMetrics: selectedMetrics
        )
        let hostingView = NSHostingView(rootView: rootView)

        if let button = statusItem.button {
            // Clear button title and image
            button.title = ""
            button.image = nil

            // Add hosting view as subview
            button.addSubview(hostingView)

            // Use Auto Layout constraints
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: button.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])

            // Set up click action
            button.target = self
            button.action = #selector(statusItemClicked)
        }

        self.statusItem = statusItem
        self.hostingView = hostingView

        // Listen for size changes from the SwiftUI view and update status item length
        sizeCancellable = sizePassthrough.sink { [weak self] size in
            self?.statusItem?.length = size.width + 12
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

    private func updateStatusView() {
        let rootView = StatusItemView(
            sizePassthrough: sizePassthrough,
            keystrokeCount: keystrokeCount,
            wordCount: wordCount,
            clickCount: clickCount,
            distanceText: distanceText,
            selectedMetrics: selectedMetrics
        )
        hostingView?.rootView = rootView
    }

    func updateSelectedMetrics(_ metrics: Set<Metric>) {
        selectedMetrics = metrics
        updateStatusView()
    }

    func updateSelectedMetrics(_ metrics: Set<HistoryMetric>) {
        // Compatibility method - convert to Metric
        let metricSet: Set<Metric> = Set(metrics.compactMap { metric in
            switch metric {
            case .keystrokes: return .keystrokes
            case .words: return .words
            case .clicks: return .clicks
            case .distance: return .distance
            default: return nil
            }
        })
        updateSelectedMetrics(metricSet)
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
    var selectedMetrics: Set<Metric>

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

    private var metricViews: [AnyView] {
        var views: [AnyView] = []

        if selectedMetrics.contains(.keystrokes) {
            views.append(AnyView(
                MetricItem(icon: "keyboard", value: formatCount(keystrokeCount))
            ))
        }
        if selectedMetrics.contains(.words) {
            views.append(AnyView(
                MetricItem(icon: "text.alignleft", value: formatCount(wordCount))
            ))
        }
        if selectedMetrics.contains(.clicks) {
            views.append(AnyView(
                MetricItem(icon: "cursorarrow.click", value: formatCount(clickCount))
            ))
        }
        if selectedMetrics.contains(.distance), let distance = distanceText {
            views.append(AnyView(
                MetricItem(icon: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left", value: distance)
            ))
        }

        return views
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<metricViews.count, id: \.self) { index in
                metricViews[index]
            }
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

private struct MetricItem: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13))
            Text(value)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
        }
    }
}
