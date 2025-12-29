import Cocoa
import Combine
import os

/// Monitors global mouse events using CGEventTap
final class MouseMonitor: ObservableObject {
    @Published private(set) var mouseClicks: UInt64 = 0
    @Published private(set) var mouseScrolls: UInt64 = 0
    @Published private(set) var mouseDistance: Double = 0
    @Published private(set) var isRunning = false

    // Pending counts (accumulated on callback thread, flushed periodically)
    private var pendingClicks: UInt64 = 0
    private var pendingScrolls: UInt64 = 0
    private var pendingDistance: Double = 0.0

    // Fast lock for callback thread
    private var lock = os_unfair_lock()

    // Track last mouse position for distance calculation
    private var lastMousePosition: CGPoint = .zero

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoopThread: Thread?
    private var backgroundRunLoop: CFRunLoop?
    private var flushTimer: Timer?

    deinit {
        stop()
    }

    /// Start monitoring mouse events
    func start() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        guard eventTap == nil else { return }

        // Event mask for mouse events
        let eventMask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue)

        // Create the event tap
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }

                let monitor = Unmanaged<MouseMonitor>.fromOpaque(refcon).takeUnretainedValue()

                switch type {
                case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                    os_unfair_lock_lock(&monitor.lock)
                    monitor.pendingClicks += 1
                    os_unfair_lock_unlock(&monitor.lock)

                case .scrollWheel:
                    let deltaY = abs(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
                    let deltaX = abs(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
                    os_unfair_lock_lock(&monitor.lock)
                    monitor.pendingScrolls += UInt64(max(0, deltaY + deltaX))
                    os_unfair_lock_unlock(&monitor.lock)

                case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                    let location = event.location
                    os_unfair_lock_lock(&monitor.lock)
                    if monitor.lastMousePosition.x != 0 || monitor.lastMousePosition.y != 0 {
                        let dx = location.x - monitor.lastMousePosition.x
                        let dy = location.y - monitor.lastMousePosition.y
                        let distance = sqrt(dx * dx + dy * dy)
                        monitor.pendingDistance += distance
                    }
                    monitor.lastMousePosition = location
                    os_unfair_lock_unlock(&monitor.lock)

                default:
                    break
                }

                // Handle tap being disabled by system
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = monitor.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap = eventTap else {
            return
        }

        // Create run loop source
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

        // Run on a background thread
        runLoopThread = Thread { [weak self] in
            guard let self = self, let source = self.runLoopSource else { return }

            let runLoop = CFRunLoopGetCurrent()
            os_unfair_lock_lock(&self.lock)
            self.backgroundRunLoop = runLoop
            os_unfair_lock_unlock(&self.lock)

            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)

            CFRunLoopRun()
        }
        runLoopThread?.name = "MouseMonitor"
        runLoopThread?.start()

        // Start flush timer on main queue (100ms interval)
        DispatchQueue.main.async {
            self.isRunning = true
            self.flushTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.flushPendingCounts()
            }
        }
    }

    /// Flush accumulated counts to published properties
    private func flushPendingCounts() {
        os_unfair_lock_lock(&lock)
        let clicks = pendingClicks
        let scrolls = pendingScrolls
        let distance = pendingDistance
        pendingClicks = 0
        pendingScrolls = 0
        pendingDistance = 0.0
        os_unfair_lock_unlock(&lock)

        if clicks > 0 || scrolls > 0 || distance > 0 {
            mouseClicks += clicks
            mouseScrolls += scrolls
            mouseDistance += distance
        }
    }

    /// Stop monitoring mouse events
    func stop() {
        flushTimer?.invalidate()
        flushTimer = nil

        flushPendingCounts()

        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        guard let eventTap = eventTap else { return }

        CGEvent.tapEnable(tap: eventTap, enable: false)

        if let runLoop = backgroundRunLoop {
            CFRunLoopStop(runLoop)
        }

        if let thread = runLoopThread, !thread.isCancelled {
            thread.cancel()
        }

        self.eventTap = nil
        self.runLoopSource = nil
        self.runLoopThread = nil
        self.backgroundRunLoop = nil

        DispatchQueue.main.async {
            self.isRunning = false
        }
    }
}
