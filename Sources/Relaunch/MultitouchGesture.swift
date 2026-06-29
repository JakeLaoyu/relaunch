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
private final class GestureState {
    var onTrigger: (() -> Void)?
    var tracking = false
    var startSpread: Float = 0
    var lastFire: Double = 0
}
private let state = GestureState()

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
    // Thumb + three fingers == 4; allow 5 for slightly sloppy grips.
    guard count == 4 || count == 5 else {
        state.tracking = false
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

    if !state.tracking {
        state.tracking = true
        state.startSpread = spread
        return 0
    }

    // Keep the baseline at the widest spread seen so an outward move re-arms it.
    if spread > state.startSpread { state.startSpread = spread }

    // Fire on a decisive inward pinch.
    if state.startSpread > 0.16, spread < state.startSpread * 0.55 {
        if timestamp - state.lastFire > 1.0 {
            state.lastFire = timestamp
            state.tracking = false
            let trigger = state.onTrigger
            DispatchQueue.main.async { trigger?() }
        }
    }
    return 0
}

final class MultitouchGesture {
    private var lib: UnsafeMutableRawPointer?
    private var devices: [UnsafeMutableRawPointer] = []
    private var stopFn: (@convention(c) (UnsafeMutableRawPointer, Int32) -> Void)?
    private var started = false

    init(onTrigger: @escaping () -> Void) {
        state.onTrigger = onTrigger
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
        let n = CFArrayGetCount(list)
        for i in 0..<n {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            register(device, contactFrameCallback)
            startDevice(device, 0)
            devices.append(device)
        }
        started = true
    }

    func stop() {
        guard started else { return }
        for device in devices { stopFn?(device, 0) }
        devices.removeAll()
        started = false
    }
}
