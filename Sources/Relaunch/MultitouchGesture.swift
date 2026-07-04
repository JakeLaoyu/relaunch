import Foundation
import CoreFoundation
import AppKit

// Trackpad pinch detection via the private MultitouchSupport framework, loaded
// at runtime with dlopen so there is no build-time link dependency.
//
// We read raw finger contacts and detect the classic Launchpad gesture: thumb
// plus three fingers pinching inward (also fires for a four-finger pinch).
//
// Each contact in the callback buffer is a fixed-size record; we read the few
// fields we need by byte offset rather than mirroring the whole C struct, which
// avoids depending on Swift's struct layout matching C exactly.
//   offset 32: normalized.position.x  (Float)
//   offset 36: normalized.position.y  (Float)
//   offset 48: size                   (Float)
private let kFingerStride = 96
private let kSizeOffset = 48
private let kPosXOffset = 32
private let kPosYOffset = 36

private typealias MTContactCallback =
    @convention(c) (Int32, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

/// Per-device tracking between frames. Spread values are only comparable while
/// the same fingers stay down and the hand stays put, so the baseline is
/// re-anchored whenever the contact count changes (a finger landing or lifting
/// shifts the mean spread abruptly) or the centroid translates (a swipe moves
/// the whole hand; a pinch converges in place).
private struct TrackState {
    var count: Int
    var maxSpread: Float
    var minSpread: Float
    var anchorX: Float
    var anchorY: Float
}

/// Shared mutable state for the C callback (which cannot capture context).
/// Callbacks arrive on a thread per device, so access goes through the lock,
/// and pinch tracking is kept per device — otherwise idle frames from a second
/// trackpad would reset the active one's tracking mid-pinch.
private final class GestureState {
    let lock = NSLock()
    var onPinch: (() -> Void)?
    var onSpread: (() -> Void)?
    var track: [Int32: TrackState] = [:]
    var lastFire: Double = 0
}
private let state = GestureState()

// Diagnostic trace, off unless `defaults write com.mindhex.relaunch mtDebug -bool true`.
private let mtDebug = UserDefaults.standard.bool(forKey: "mtDebug")
private func mtlog(_ s: String) {
    guard mtDebug, let d = (s + "\n").data(using: .utf8) else { return }
    let url = URL(fileURLWithPath: "/tmp/relaunch-mt.log")
    if let h = try? FileHandle(forWritingTo: url) {
        defer { try? h.close() }
        h.seekToEndOfFile()
        h.write(d)
    } else {
        try? d.write(to: url)
    }
}

private func contactFrameCallback(_ device: Int32,
                                  _ data: UnsafeMutableRawPointer?,
                                  _ fingerCount: Int32,
                                  _ timestamp: Double,
                                  _ frame: Int32) -> Int32 {
    guard let data else { return 0 }

    var xs: [Float] = []
    var ys: [Float] = []
    for i in 0..<Int(fingerCount) {
        let base = data.advanced(by: i * kFingerStride)
        let size = base.load(fromByteOffset: kSizeOffset, as: Float.self)
        guard size > 0.05 else { continue }   // ignore stray/ghost contacts
        xs.append(base.load(fromByteOffset: kPosXOffset, as: Float.self))
        ys.append(base.load(fromByteOffset: kPosYOffset, as: Float.self))
    }

    let count = xs.count
    // Accept 3–5 contacts: the classic gesture is thumb + three fingers, but
    // trackpads often report only 3 (a finger merges or the thumb reads weak).
    guard count >= 3, count <= 5 else {
        state.lock.lock()
        state.track[device] = nil
        state.lock.unlock()
        return 0
    }

    let cx = xs.reduce(0, +) / Float(count)
    let cy = ys.reduce(0, +) / Float(count)
    var spread: Float = 0
    for i in 0..<count {
        let dx = xs[i] - cx, dy = ys[i] - cy
        spread += (dx * dx + dy * dy).squareRoot()
    }
    spread /= Float(count)

    state.lock.lock()
    // Re-anchor whenever the finger set or hand position stops matching the
    // baseline. Both are swipe signatures, not pinch/spread ones:
    //  - count change: a finger landing or lifting (staggered touchdown, or a
    //    lift at the end of a swipe) shifts the mean spread of the remaining
    //    contacts in one frame, which used to read as a "pinch".
    //  - centroid translation: a swipe moves the whole hand across the pad
    //    (centroid travels 0.2+), while a real pinch/spread converges or
    //    expands around a nearly fixed centroid (drift well under 0.1).
    let dxA = cx - (state.track[device]?.anchorX ?? cx)
    let dyA = cy - (state.track[device]?.anchorY ?? cy)
    let travel = (dxA * dxA + dyA * dyA).squareRoot()
    guard var t = state.track[device], t.count == count, travel < 0.10 else {
        state.track[device] = TrackState(count: count, maxSpread: spread,
                                         minSpread: spread, anchorX: cx, anchorY: cy)
        state.lock.unlock()
        return 0
    }
    // Baselines ride the extremes so a move in one direction re-arms the other.
    if spread > t.maxSpread { t.maxSpread = spread }
    if spread < t.minSpread { t.minSpread = spread }
    state.track[device] = t

    // Fire mid-gesture. Tuned to real trackpad data: a thumb + three-finger
    // pinch starts near spread ~0.27–0.32 and only reaches ~71–75% of its
    // start before a finger lifts (the deepest logged pinch: 0.268 → 0.191),
    // so require a clear absolute change plus a modest ratio. The spread-out
    // gesture mirrors the pinch with the same thresholds.
    let drop = t.maxSpread - spread
    let rise = spread - t.minSpread
    var trigger: (() -> Void)?
    if timestamp - state.lastFire > 1.0 {
        if t.maxSpread > 0.16, drop > 0.055, spread < t.maxSpread * 0.8 {
            trigger = state.onPinch
        } else if spread > 0.16, rise > 0.055, t.minSpread < spread * 0.8 {
            trigger = state.onSpread
        }
        if trigger != nil {
            state.lastFire = timestamp
            state.track[device] = nil
        }
    }
    state.lock.unlock()

    mtlog("  n=\(count) max=\(t.maxSpread) min=\(t.minSpread) spread=\(spread) travel=\(travel)")
    if let trigger {
        mtlog("FIRE")
        DispatchQueue.main.async { trigger() }
    }
    return 0
}

final class MultitouchGesture {
    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias DeviceFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void

    private var lib: UnsafeMutableRawPointer?
    private var deviceList: CFArray?   // owns the MTDeviceRefs in `devices`
    private var devices: [UnsafeMutableRawPointer] = []
    private var createListFn: CreateListFn?
    private var stopFn: DeviceFn?
    private var started = false
    private var refreshTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(onPinch: @escaping () -> Void, onSpread: (() -> Void)? = nil) {
        state.lock.lock()
        state.onPinch = onPinch
        state.onSpread = onSpread
        state.lock.unlock()
    }

    func start() {
        guard !started else { return }

        if lib == nil {
            let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
            lib = dlopen(path, RTLD_NOW)
        }
        guard let lib else {
            NSLog("Relaunch: could not load MultitouchSupport")
            return
        }

        guard let createListSym = dlsym(lib, "MTDeviceCreateList"),
              let registerSym = dlsym(lib, "MTRegisterContactFrameCallback"),
              let startSym = dlsym(lib, "MTDeviceStart"),
              let stopSym = dlsym(lib, "MTDeviceStop") else {
            NSLog("Relaunch: missing MultitouchSupport symbols")
            return
        }

        typealias RegisterFn = @convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void

        let createList = unsafeBitCast(createListSym, to: CreateListFn.self)
        let register = unsafeBitCast(registerSym, to: RegisterFn.self)
        let startDevice = unsafeBitCast(startSym, to: DeviceFn.self)
        createListFn = createList
        stopFn = unsafeBitCast(stopSym, to: DeviceFn.self)

        guard let list = createList()?.takeRetainedValue() else { return }
        // Keep the array alive while started: the raw device pointers below are
        // not individually retained, so their lifetime rides on the array's.
        deviceList = list
        let n = CFArrayGetCount(list)
        for i in 0..<n {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            register(device, contactFrameCallback)
            startDevice(device, 0)
            devices.append(device)
        }
        mtlog("MT start: devices=\(devices.count)")
        started = true
        watchForDeviceChanges()
    }

    func stop() {
        guard started else { return }
        for device in devices { stopFn?(device, 0) }
        devices.removeAll()
        deviceList = nil
        state.lock.lock()
        state.track.removeAll()
        state.lock.unlock()
        refreshTimer?.invalidate(); refreshTimer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        started = false
    }

    /// The device list is captured once at start(), so a trackpad plugged in
    /// later — or devices re-created after sleep — would never deliver the
    /// gesture. Re-enumerate on wake, and poll slowly for count changes.
    private func watchForDeviceChanges() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.restart() }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, let createList = self.createListFn else { return }
            var count = 0
            if let list = createList()?.takeRetainedValue() { count = CFArrayGetCount(list) }
            if count != self.devices.count { self.restart() }
        }
    }

    private func restart() {
        guard started else { return }
        stop()
        start()
    }
}
