import AppKit

// Enforce single instance using a Mach bootstrap port name.
// NSWorkspace.runningApplications misses accessory-policy apps, so we use a
// named port that only the first instance can claim.
import Foundation

let portName = "com.grabbit.app.single-instance" as CFString
var port = CFMessagePortCreateLocal(nil, portName, nil, nil, nil)
if port == nil {
    // Port already claimed — another instance is running. Exit immediately.
    exit(0)
}
// Keep port alive for the lifetime of the process.
CFRunLoopAddSource(CFRunLoopGetMain(),
                   CFMessagePortCreateRunLoopSource(nil, port, 0),
                   .commonModes)

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no dock icon until an editor opens
let delegate = AppDelegate()
app.delegate = delegate
app.run()
