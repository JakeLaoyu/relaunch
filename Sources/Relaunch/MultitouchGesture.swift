import Foundation
import CoreFoundation

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

/// Shared mutable state for the C callback (which cannot capture context).
/// Callbacks arrive on a thread per device, so access goes through the lock,
/// and pinch tracking is kept per device — otherwise idle frames from a second
/// trackpad would reset the active one's tracking mid-pinch.
private final class GestureState {
    let lock = NSLock()
    var onTrigger: (() -> Void)?
    var startSpread: [Int32: Float] = [:]   // device → widest spread this contact
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
        state.startSpread[device] = nil
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
    guard var start = state.startSpread[device] else {
        state.startSpread[device] = spread
        state.lock.unlock()
        return 0
    }
    // Keep the baseline at the widest spread seen so an outward move re-arms it.
    if spread > start { start = spread; state.startSpread[device] = start }

    // Fire mid-pinch. Tuned to real trackpad data: a thumb + three-finger
    // pinch starts near spread ~0.27–0.32 and only reaches ~71–75% of its
    // start before a finger lifts (the deepest logged pinch: 0.268 → 0.191),
    // so require a clear absolute drop plus a modest ratio. A four-finger
    // *swipe* translates without converging (observed drop < 0.005), so it
    // stays far from these conditions.
    let drop = start - spread
    var trigger: (() -> Void)?
    if start > 0.16, drop > 0.055, spread < start * 0.8, timestamp - state.lastFire > 1.0 {
        state.lastFire = timestamp
        state.startSpread[device] = nil
        trigger = state.onTrigger
    }
    state.lock.unlock()

    mtlog("  n=\(count) start=\(start) spread=\(spread) drop=\(drop)")
    if let trigger {
        mtlog("FIRE")
        DispatchQueue.main.async { trigger() }
    }
    return 0
}

final class MultitouchGesture {
    private var lib: UnsafeMutableRawPointer?
    private var deviceList: CFArray?   // owns the MTDeviceRefs in `devices`
    private var devices: [UnsafeMutableRawPointer] = []
    private var stopFn: (@convention(c) (UnsafeMutableRawPointer, Int32) -> Void)?
    private var started = false

    init(onTrigger: @escaping () -> Void) {
        state.lock.lock()
        state.onTrigger = onTrigger
        state.lock.unlock()
    }

    func start() {
        guard !started else { return }

        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let lib = dlopen(path, RTLD_NOW) else {
            NSLog("Relaunch: could not load MultitouchSupport")
            return
        }
        self.lib = lib

        guard let createListSym = dlsym(lib, "MTDeviceCreateList"),
              let registerSym = dlsym(lib, "MTRegisterContactFrameCallback"),
              let startSym = dlsym(lib, "MTDeviceStart"),
              let stopSym = dlsym(lib, "MTDeviceStop") else {
            NSLog("Relaunch: missing MultitouchSupport symbols")
            return
        }

        typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
        typealias RegisterFn = @convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void
        typealias StartFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void

        let createList = unsafeBitCast(createListSym, to: CreateListFn.self)
        let register = unsafeBitCast(registerSym, to: RegisterFn.self)
        let startDevice = unsafeBitCast(startSym, to: StartFn.self)
        stopFn = unsafeBitCast(stopSym, to: StartFn.self)

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
    }

    func stop() {
        guard started else { return }
        for device in devices { stopFn?(device, 0) }
        devices.removeAll()
        deviceList = nil
        state.lock.lock()
        state.startSpread.removeAll()
        state.lock.unlock()
        started = false
    }
}
