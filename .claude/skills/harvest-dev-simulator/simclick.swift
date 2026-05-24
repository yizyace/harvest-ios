import CoreGraphics
import Foundation

// Post a real left-click at SCREEN coordinates (points, top-left origin).
//   xcrun swift simclick.swift X Y
// Works against the iOS Simulator content where `osascript "click at"` does not.
let a = CommandLine.arguments
guard a.count >= 3, let x = Double(a[1]), let y = Double(a[2]) else {
    FileHandle.standardError.write("usage: simclick X Y\n".data(using: .utf8)!)
    exit(2)
}
let p = CGPoint(x: x, y: y)
let src = CGEventSource(stateID: .hidSystemState)
CGWarpMouseCursorPosition(p)
usleep(20000)
CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(60000)
CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
print("clicked \(Int(x)),\(Int(y))")
