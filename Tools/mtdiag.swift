// Multitouch diagnostic. Run in Terminal, then do the thumb + three-finger
// pinch on the trackpad a few times:
//
//     swift Tools/mtdiag.swift
//
// It prints, for every frame with >=3 contacts: the finger count and the mean
// spread (distance to centroid, normalized 0..1). Watch how `spread` changes as
// you pinch in. Ctrl-C to stop. Paste the output back.

import Foundation
import CoreFoundation

let stride = 96
typealias CB = @convention(c) (Int32, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

var frames = 0
var maxFingers = 0

let callback: CB = { _, data, n, ts, _ in
    guard let data else { return 0 }
    var xs: [Float] = [], ys: [Float] = []
    for i in 0..<Int(n) {
        let b = data.advanced(by: i * stride)
        let size = b.load(fromByteOffset: 48, as: Float.self)
        if size > 0.05 {
            xs.append(b.load(fromByteOffset: 32, as: Float.self))
            ys.append(b.load(fromByteOffset: 36, as: Float.self))
        }
    }
    frames += 1
    let c = xs.count
    if c > maxFingers { maxFingers = c }
    guard c >= 3 else { return 0 }
    let cx = xs.reduce(0,+)/Float(c), cy = ys.reduce(0,+)/Float(c)
    var spread: Float = 0
    for i in 0..<c { let dx = xs[i]-cx, dy = ys[i]-cy; spread += (dx*dx+dy*dy).squareRoot() }
    spread /= Float(c)
    FileHandle.standardError.write("fingers=\(c)  spread=\(String(format: "%.3f", spread))\n".data(using: .utf8)!)
    return 0
}

let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
guard let lib = dlopen(path, RTLD_NOW) else { print("dlopen FAILED"); exit(1) }
typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
typealias Register = @convention(c) (UnsafeMutableRawPointer, CB) -> Void
typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
let createList = unsafeBitCast(dlsym(lib, "MTDeviceCreateList")!, to: CreateList.self)
let register = unsafeBitCast(dlsym(lib, "MTRegisterContactFrameCallback")!, to: Register.self)
let start = unsafeBitCast(dlsym(lib, "MTDeviceStart")!, to: Start.self)

func err(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

guard let list = createList()?.takeRetainedValue() else { err("no device list"); exit(1) }
let count = CFArrayGetCount(list)
err("devices: \(count)  — now REST 4 fingers on the trackpad, then pinch in a few times…")
for i in 0..<count {
    guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
    let dev = UnsafeMutableRawPointer(mutating: raw)
    register(dev, callback)
    start(dev, 0)
}

// Print a heartbeat so we know whether callbacks arrive at all.
Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
    FileHandle.standardError.write("[\(frames) frames so far, maxFingers=\(maxFingers)]\n".data(using: .utf8)!)
}
RunLoop.main.run()
