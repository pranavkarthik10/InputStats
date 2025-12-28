import Foundation
import Combine
import Cocoa

/// Central coordinator for all stats data - handles local storage, iCloud sync, and CRDT merging
final class StatsRepository: ObservableObject {
    @Published private(set) var todayStats: DailyStats?
    @Published private(set) var recentStats: [DailyStats] = []
    @Published private(set) var yesterdayCount: UInt64 = 0
    @Published private(set) var sevenDayAvg: UInt64 = 0
    @Published private(set) var thirtyDayAvg: UInt64 = 0
    @Published private(set) var recordCount: UInt64 = 0
    @Published private(set) var recordDate: String = ""

    // Word stats
    @Published private(set) var yesterdayWords: UInt64 = 0
    @Published private(set) var sevenDayAvgWords: UInt64 = 0
    @Published private(set) var thirtyDayAvgWords: UInt64 = 0
    @Published private(set) var recordWords: UInt64 = 0
    @Published private(set) var recordWordsDate: String = ""

    // Mouse stats - clicks
    @Published private(set) var yesterdayClicks: UInt64 = 0
    @Published private(set) var sevenDayAvgClicks: UInt64 = 0
    @Published private(set) var thirtyDayAvgClicks: UInt64 = 0
    @Published private(set) var recordClicks: UInt64 = 0
    @Published private(set) var recordClicksDate: String = ""

    // Mouse stats - scrolls
    @Published private(set) var yesterdayScrolls: UInt64 = 0
    @Published private(set) var sevenDayAvgScrolls: UInt64 = 0
    @Published private(set) var thirtyDayAvgScrolls: UInt64 = 0
    @Published private(set) var recordScrolls: UInt64 = 0
    @Published private(set) var recordScrollsDate: String = ""

    // Mouse stats - distance
    @Published private(set) var yesterdayDistance: Double = 0.0
    @Published private(set) var sevenDayAvgDistance: Double = 0.0
    @Published private(set) var thirtyDayAvgDistance: Double = 0.0
    @Published private(set) var recordDistance: Double = 0.0
    @Published private(set) var recordDistanceDate: String = ""

    private let localStore = LocalStore()
    private let cloudSync = iCloudSync()
    private var keystrokeMonitor: KeystrokeMonitor?
    private var mouseMonitor: MouseMonitor?
    private var statsCache: [String: DailyStats] = [:]

    private var saveTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var lastKeystrokeCount: UInt64 = 0
    private var lastWordCount: UInt64 = 0
    private var lastMouseClicks: UInt64 = 0
    private var lastMouseScrolls: UInt64 = 0
    private var lastMouseDistance: Double = 0.0

    init() {
        loadInitialData()
        setupSyncObserver()
    }

    deinit {
        saveTask?.cancel()
        keystrokeMonitor?.stop()
        mouseMonitor?.stop()
        forceSave()
    }

    /// Set up keystroke monitoring with permission check
    func setupKeystrokeMonitoring() {
        guard keystrokeMonitor == nil else { return }

        let monitor = KeystrokeMonitor()
        keystrokeMonitor = monitor

        // Monitor keystroke count changes
        monitor.$keystrokeCount
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newCount in
                guard let self = self else { return }
                let delta = newCount - self.lastKeystrokeCount
                if delta > 0 {
                    self.recordKeystrokes(delta)
                }
                self.lastKeystrokeCount = newCount
            }
            .store(in: &cancellables)

        // Monitor word count changes
        monitor.$wordCount
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newCount in
                guard let self = self else { return }
                let delta = newCount - self.lastWordCount
                if delta > 0 {
                    self.recordWords(delta)
                }
                self.lastWordCount = newCount
            }
            .store(in: &cancellables)

        // Start monitoring if we have permission
        startMonitoringIfAuthorized()
    }

    /// Set up mouse monitoring with permission check
    func setupMouseMonitoring() {
        guard mouseMonitor == nil else { return }

        let monitor = MouseMonitor()
        mouseMonitor = monitor

        // Monitor mouse click changes
        monitor.$mouseClicks
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newCount in
                guard let self = self else { return }
                let delta = newCount - self.lastMouseClicks
                if delta > 0 {
                    self.recordMouseClicks(delta)
                }
                self.lastMouseClicks = newCount
            }
            .store(in: &cancellables)

        // Monitor mouse scroll changes
        monitor.$mouseScrolls
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newCount in
                guard let self = self else { return }
                let delta = newCount - self.lastMouseScrolls
                if delta > 0 {
                    self.recordMouseScroll(delta)
                }
                self.lastMouseScrolls = newCount
            }
            .store(in: &cancellables)

        // Monitor mouse distance changes
        monitor.$mouseDistance
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newDistance in
                guard let self = self else { return }
                let delta = newDistance - self.lastMouseDistance
                if delta > 0 {
                    self.recordMouseDistance(delta)
                }
                self.lastMouseDistance = newDistance
            }
            .store(in: &cancellables)

        // Start monitoring if we have permission
        startMonitoringIfAuthorized()
    }

    /// Check permission and start monitoring
    func startMonitoringIfAuthorized() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        if AXIsProcessTrustedWithOptions(options as CFDictionary) {
            keystrokeMonitor?.start()
            mouseMonitor?.start()
        }
    }

    /// Load data from local store and iCloud
    private func loadInitialData() {
        // Load local first
        statsCache = localStore.loadAll()

        // Merge with iCloud data
        let cloudStats = cloudSync.loadAll()
        for (dateID, cloudStat) in cloudStats {
            if var localStat = statsCache[dateID] {
                localStat.merge(with: cloudStat)
                statsCache[dateID] = localStat
            } else {
                statsCache[dateID] = cloudStat
            }
        }

        updatePublishedStats()
    }

    /// Set up observer for iCloud changes from other devices
    private func setupSyncObserver() {
        cloudSync.observeChanges { [weak self] remoteStats in
            DispatchQueue.main.async {
                self?.handleRemoteChanges(remoteStats)
            }
        }
    }

    /// Handle stats received from iCloud
    private func handleRemoteChanges(_ remoteStats: [DailyStats]) {
        for remoteStat in remoteStats {
            if var localStat = statsCache[remoteStat.id] {
                localStat.merge(with: remoteStat)
                statsCache[remoteStat.id] = localStat
                localStore.save(localStat)
            } else {
                statsCache[remoteStat.id] = remoteStat
                localStore.save(remoteStat)
            }
        }
        updatePublishedStats()
    }

    /// Record a keystroke for today
    func recordKeystroke() {
        let today = DateHelpers.todayID()

        if var stats = statsCache[today] {
            stats.increment()
            statsCache[today] = stats
        } else {
            var stats = DailyStats()
            stats.increment()
            statsCache[today] = stats
        }

        updatePublishedStats()
        scheduleSave()
    }

    /// Record multiple keystrokes at once (for batching)
    func recordKeystrokes(_ count: UInt64) {
        guard count > 0 else { return }

        let today = DateHelpers.todayID()

        if var stats = statsCache[today] {
            stats.increment(by: count)
            statsCache[today] = stats
        } else {
            var stats = DailyStats()
            stats.increment(by: count)
            statsCache[today] = stats
        }

        updatePublishedStats()
        scheduleSave()
    }

    /// Record multiple words at once (for batching)
    func recordWords(_ count: UInt64) {
        guard count > 0 else { return }

        let today = DateHelpers.todayID()

        if var stats = statsCache[today] {
            stats.incrementWords(by: count)
            statsCache[today] = stats
        } else {
            var stats = DailyStats()
            stats.incrementWords(by: count)
            statsCache[today] = stats
        }

        updatePublishedStats()
        scheduleSave()
    }

    /// Record multiple mouse clicks at once (for batching)
    func recordMouseClicks(_ count: UInt64) {
        guard count > 0 else { return }

        let today = DateHelpers.todayID()

        if var stats = statsCache[today] {
            stats.incrementClicks(by: count)
            statsCache[today] = stats
        } else {
            var stats = DailyStats()
            stats.incrementClicks(by: count)
            statsCache[today] = stats
        }

        updatePublishedStats()
        scheduleSave()
    }

    /// Record multiple mouse scroll events at once (for batching)
    func recordMouseScroll(_ count: UInt64) {
        guard count > 0 else { return }

        let today = DateHelpers.todayID()

        if var stats = statsCache[today] {
            stats.incrementScrolls(by: count)
            statsCache[today] = stats
        } else {
            var stats = DailyStats()
            stats.incrementScrolls(by: count)
            statsCache[today] = stats
        }

        updatePublishedStats()
        scheduleSave()
    }

    /// Record mouse distance (pixels)
    func recordMouseDistance(_ pixels: Double) {
        guard pixels > 0 else { return }

        let today = DateHelpers.todayID()

        if var stats = statsCache[today] {
            stats.addDistance(pixels)
            statsCache[today] = stats
        } else {
            var stats = DailyStats()
            stats.addDistance(pixels)
            statsCache[today] = stats
        }

        updatePublishedStats()
        scheduleSave()
    }

    /// Debounced save to avoid excessive I/O
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            persistCurrentStats()
        }
    }

    /// Actually persist to local and cloud
    private func persistCurrentStats() {
        let today = DateHelpers.todayID()
        guard let stats = statsCache[today] else { return }
        localStore.save(stats)
        cloudSync.save(stats)
    }

    /// Update the published properties for UI
    private func updatePublishedStats() {
        let today = DateHelpers.todayID()
        todayStats = statsCache[today]

        // Get all stats sorted newest first
        let allStats = statsCache.values.sorted { $0.id > $1.id }
        recentStats = Array(allStats.prefix(7))

        // Yesterday
        let yesterday = DateHelpers.dateID(daysAgo: 1)
        yesterdayCount = statsCache[yesterday]?.totalKeystrokes ?? 0
        yesterdayWords = statsCache[yesterday]?.totalWords ?? 0
        yesterdayClicks = statsCache[yesterday]?.totalMouseClicks ?? 0
        yesterdayScrolls = statsCache[yesterday]?.totalMouseScroll ?? 0
        yesterdayDistance = statsCache[yesterday]?.totalMouseDistance ?? 0.0

        // 7-day average (excluding today)
        let last7Days = (1...7).compactMap { statsCache[DateHelpers.dateID(daysAgo: $0)] }
        if !last7Days.isEmpty {
            let total = last7Days.reduce(UInt64(0)) { $0 + $1.totalKeystrokes }
            sevenDayAvg = total / UInt64(last7Days.count)
            let totalWords = last7Days.reduce(UInt64(0)) { $0 + $1.totalWords }
            sevenDayAvgWords = totalWords / UInt64(last7Days.count)
            let totalClicks = last7Days.reduce(UInt64(0)) { $0 + $1.totalMouseClicks }
            sevenDayAvgClicks = totalClicks / UInt64(last7Days.count)
            let totalScrolls = last7Days.reduce(UInt64(0)) { $0 + $1.totalMouseScroll }
            sevenDayAvgScrolls = totalScrolls / UInt64(last7Days.count)
            let totalDistance = last7Days.reduce(0.0) { $0 + $1.totalMouseDistance }
            sevenDayAvgDistance = totalDistance / Double(last7Days.count)
        } else {
            sevenDayAvg = 0
            sevenDayAvgWords = 0
            sevenDayAvgClicks = 0
            sevenDayAvgScrolls = 0
            sevenDayAvgDistance = 0.0
        }

        // 30-day average (excluding today)
        let last30Days = (1...30).compactMap { statsCache[DateHelpers.dateID(daysAgo: $0)] }
        if !last30Days.isEmpty {
            let total = last30Days.reduce(UInt64(0)) { $0 + $1.totalKeystrokes }
            thirtyDayAvg = total / UInt64(last30Days.count)
            let totalWords = last30Days.reduce(UInt64(0)) { $0 + $1.totalWords }
            thirtyDayAvgWords = totalWords / UInt64(last30Days.count)
            let totalClicks = last30Days.reduce(UInt64(0)) { $0 + $1.totalMouseClicks }
            thirtyDayAvgClicks = totalClicks / UInt64(last30Days.count)
            let totalScrolls = last30Days.reduce(UInt64(0)) { $0 + $1.totalMouseScroll }
            thirtyDayAvgScrolls = totalScrolls / UInt64(last30Days.count)
            let totalDistance = last30Days.reduce(0.0) { $0 + $1.totalMouseDistance }
            thirtyDayAvgDistance = totalDistance / Double(last30Days.count)
        } else {
            thirtyDayAvg = 0
            thirtyDayAvgWords = 0
            thirtyDayAvgClicks = 0
            thirtyDayAvgScrolls = 0
            thirtyDayAvgDistance = 0.0
        }

        // Record (all time high) - keystrokes
        if let record = allStats.max(by: { $0.totalKeystrokes < $1.totalKeystrokes }) {
            recordCount = record.totalKeystrokes
            recordDate = DateHelpers.shortDisplayString(from: record.id)
        }

        // Record (all time high) - words
        if let record = allStats.max(by: { $0.totalWords < $1.totalWords }) {
            recordWords = record.totalWords
            recordWordsDate = DateHelpers.shortDisplayString(from: record.id)
        }

        // Record (all time high) - clicks
        if let record = allStats.max(by: { $0.totalMouseClicks < $1.totalMouseClicks }) {
            recordClicks = record.totalMouseClicks
            recordClicksDate = DateHelpers.shortDisplayString(from: record.id)
        }

        // Record (all time high) - scrolls
        if let record = allStats.max(by: { $0.totalMouseScroll < $1.totalMouseScroll }) {
            recordScrolls = record.totalMouseScroll
            recordScrollsDate = DateHelpers.shortDisplayString(from: record.id)
        }

        // Record (all time high) - distance
        if let record = allStats.max(by: { $0.totalMouseDistance < $1.totalMouseDistance }) {
            recordDistance = record.totalMouseDistance
            recordDistanceDate = DateHelpers.shortDisplayString(from: record.id)
        }
    }

    /// Force save (call on app termination)
    func forceSave() {
        saveTask?.cancel()
        let today = DateHelpers.todayID()
        if let stats = statsCache[today] {
            localStore.save(stats)
            cloudSync.save(stats)
        }
    }

    /// Get all stats for history view
    func getAllStats() -> [DailyStats] {
        statsCache.values.sorted { $0.id > $1.id }
    }
}
