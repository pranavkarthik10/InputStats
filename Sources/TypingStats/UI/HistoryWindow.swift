import SwiftUI
import Charts

enum TimeRange: String, CaseIterable {
    case week = "7 days"
    case month = "30 days"
    case twoMonths = "60 days"

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .twoMonths: return 60
        }
    }
}

enum Metric: String, CaseIterable {
    case keystrokes = "Keystrokes"
    case words = "Words"
    case clicks = "Clicks"
    case scrolls = "Scrolls"
    case distance = "Distance"
}

struct HistoryView: View {
    let allStats: [DailyStats]
    let appSettings: AppSettings
    @State private var selectedRange: TimeRange = .month

    private var filteredStats: [DailyStats] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -selectedRange.days, to: Date()) ?? Date()
        let cutoffID = DateHelpers.dateID(from: cutoffDate)
        return allStats.filter { $0.id >= cutoffID }.sorted { $0.id < $1.id }
    }

    private func getCount(for stats: DailyStats?, metric: Metric) -> UInt64 {
        guard let stats = stats else { return 0 }
        switch metric {
        case .keystrokes: return stats.totalKeystrokes
        case .words: return stats.totalWords
        case .clicks: return stats.totalMouseClicks
        case .scrolls: return stats.totalMouseScroll
        case .distance: return UInt64(stats.totalMouseDistance)
        }
    }

    private func getDistance(for stats: DailyStats?) -> Double {
        guard let stats = stats else { return 0.0 }
        return stats.totalMouseDistance
    }

    private func chartData(for metric: Metric) -> [ChartDataPoint] {
        var points: [ChartDataPoint] = []
        for i in (0..<selectedRange.days).reversed() {
            let dateID = DateHelpers.dateID(daysAgo: i)
            let count = getCount(for: allStats.first(where: { $0.id == dateID }), metric: metric)
            if let date = DateHelpers.date(from: dateID) {
                points.append(ChartDataPoint(date: date, count: count, dateID: dateID))
            }
        }
        return points
    }

    private var maxCount: UInt64 {
        let allCounts = Metric.allCases.flatMap { metric in
            chartData(for: metric).map(\.count)
        }
        return max(allCounts.max() ?? 0, 100)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("History")
                        .font(.title2)
                        .fontWeight(.bold)

                    Spacer()

                    Picker("", selection: $selectedRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                // Charts for each metric
                ForEach(Metric.allCases, id: \.self) { metric in
                    VStack(alignment: .leading) {
                        Text(metric.rawValue)
                            .font(.headline)
                            .padding(.horizontal, 20)

                        Chart(chartData(for: metric)) { point in
                            BarMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value(metric.rawValue, point.count)
                            )
                            .foregroundStyle(Color.accentColor)
                            .cornerRadius(2)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: xAxisStride)) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                    .foregroundStyle(Color.gray.opacity(0.3))
                                AxisValueLabel(format: .dateTime.month().day())
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .trailing) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                    .foregroundStyle(Color.gray.opacity(0.3))
                                AxisValueLabel {
                                    if let count = value.as(Double.self) {
                                        Text(formatAxisValue(count, metric: metric))
                                    }
                                }
                                .foregroundStyle(Color.secondary)
                            }
                        }
                        .chartYScale(domain: 1...max(chartData(for: metric).map(\.count).max() ?? 100, 100))
                        .frame(height: 200)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                        Divider()
                    }
                }

                // Daily stats list
                VStack(alignment: .leading) {
                    Text("Daily Breakdown")
                        .font(.headline)
                        .padding(.horizontal, 20)

                    ForEach((0..<selectedRange.days).reversed(), id: \.self) { i in
                        let dateID = DateHelpers.dateID(daysAgo: i)
                        if let stats = allStats.first(where: { $0.id == dateID }) {
                            HStack(alignment: .top, spacing: 20) {
                                Text(formatDate(dateID))
                                    .frame(width: 100, alignment: .leading)
                                    .font(.system(.body, design: .monospaced))

                                VStack(alignment: .leading, spacing: 4) {
                                    StatRow(label: "Keystrokes", value: formatNumber(stats.totalKeystrokes))
                                    StatRow(label: "Words", value: formatNumber(stats.totalWords))
                                    StatRow(label: "Clicks", value: formatNumber(stats.totalMouseClicks))
                                    StatRow(label: "Scrolls", value: formatNumber(stats.totalMouseScroll))
                                    StatRow(label: "Distance", value: appSettings.formatDistance(stats.totalMouseDistance))
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 4)

                            if i > 0 {
                                Divider()
                            }
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .frame(width: 650, height: 800)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var xAxisStride: Int {
        switch selectedRange {
        case .week: return 1
        case .month: return 4
        case .twoMonths: return 8
        }
    }

    private func formatDate(_ dateID: String) -> String {
        guard let date = DateHelpers.date(from: dateID) else { return dateID }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func formatNumber(_ number: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private func formatAxisValue(_ value: Double, metric: Metric) -> String {
        switch metric {
        case .distance:
            let pixels = value
            return appSettings.formatDistance(pixels)
        default:
            return formatNumber(UInt64(value))
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 80, alignment: .leading)
                .foregroundColor(.secondary)
            Text(value)
                .monospacedDigit()
        }
        .font(.system(.body, design: .monospaced))
    }
}

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let count: UInt64
    let dateID: String
}

final class HistoryWindowController {
    private var window: NSWindow?
    private var hostingController: NSHostingController<HistoryView>?
    private var closeObserver: NSObjectProtocol?

    deinit {
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func show(stats: [DailyStats], appSettings: AppSettings) {
        if let existingWindow = window {
            hostingController?.rootView = HistoryView(allStats: stats, appSettings: appSettings)
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let historyView = HistoryView(allStats: stats, appSettings: appSettings)
        let hosting = NSHostingController(rootView: historyView)
        hostingController = hosting

        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "Typing Stats History"
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.setContentSize(NSSize(width: 650, height: 800))

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
