import Foundation
import Combine

/// Manages user preferences and settings
final class AppSettings: ObservableObject {
    @Published var dpi: Double
    @Published var distanceFormat: DistanceFormat
    @Published var selectedMetrics: Set<Metric>

    private let userDefaults = UserDefaults.standard

    private enum Keys {
        static let dpi = "dpiSetting"
        static let distanceFormat = "distanceFormat"
        static let selectedMetrics = "selectedMetrics"
    }

    init() {
        let dpiValue = userDefaults.double(forKey: Keys.dpi)
        self.dpi = dpiValue == 0 ? 96.0 : dpiValue
        self.distanceFormat = DistanceFormat(rawValue: userDefaults.string(forKey: Keys.distanceFormat) ?? "mi") ?? .miles

        // Load saved metrics, default to keystrokes if none
        if let savedMetrics = userDefaults.string(forKey: Keys.selectedMetrics) {
            let metricStrings = savedMetrics.split(separator: ",").map { String($0) }
            self.selectedMetrics = Set(metricStrings.compactMap { Metric(rawValue: $0.trimmingCharacters(in: .whitespaces)) })
        } else {
            self.selectedMetrics = [.keystrokes]
        }
    }

    func saveDPI(_ value: Double) {
        guard value > 0 else { return }
        userDefaults.set(value, forKey: Keys.dpi)
        self.dpi = value
    }

    func saveDistanceFormat(_ format: DistanceFormat) {
        userDefaults.set(format.rawValue, forKey: Keys.distanceFormat)
        self.distanceFormat = format
    }

    func saveSelectedMetrics(_ metrics: Set<Metric>) {
        let metricStrings = metrics.map { $0.rawValue }.joined(separator: ",")
        userDefaults.set(metricStrings, forKey: Keys.selectedMetrics)
        self.selectedMetrics = metrics
    }

    func toggleMetric(_ metric: Metric) {
        var newMetrics = selectedMetrics
        if newMetrics.contains(metric) {
            newMetrics.remove(metric)
        } else {
            newMetrics.insert(metric)
        }
        saveSelectedMetrics(newMetrics)
    }


    func formatDistance(_ pixels: Double) -> String {
        let miles = pixelsToMiles(pixels)
        let feet = pixelsToFeet(pixels)

        switch distanceFormat {
        case .miles:
            if miles >= 1.0 {
                return String(format: "%.2f mi", miles)
            } else {
                return String(format: "%.0f ft", feet)
            }
        case .feet:
            return formatNumber(feet) + " ft"
        case .both:
            return String(format: "%.0f ft / %.2f mi", feet, miles)
        }
    }

    func pixelsToMiles(_ pixels: Double) -> Double {
        let inches = pixels / dpi
        let feet = inches / 12.0
        return feet / 5280.0
    }

    func pixelsToFeet(_ pixels: Double) -> Double {
        let inches = pixels / dpi
        return inches / 12.0
    }

    private func formatNumber(_ number: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

enum Metric: String, CaseIterable, Hashable {
    case keystrokes = "keystrokes"
    case words = "words"
    case clicks = "clicks"
    case distance = "distance"

    var displayName: String {
        switch self {
        case .keystrokes: return "Keystrokes"
        case .words: return "Words"
        case .clicks: return "Clicks"
        case .distance: return "Distance"
        }
    }

    var iconName: String {
        switch self {
        case .keystrokes: return "keyboard"
        case .words: return "text.alignleft"
        case .clicks: return "cursorarrow.click"
        case .distance: return "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left"
        }
    }
}

enum DistanceFormat: String, CaseIterable {
    case miles = "mi"
    case feet = "ft"
    case both = "both"

    var displayName: String {
        switch self {
        case .miles: return "Miles"
        case .feet: return "Feet"
        case .both: return "Both"
        }
    }
}
