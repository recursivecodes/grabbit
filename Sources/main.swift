import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no dock icon until an editor opens
let delegate = AppDelegate()
app.delegate = delegate
app.run()
