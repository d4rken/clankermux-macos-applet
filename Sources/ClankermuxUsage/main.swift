import AppKit

let application = NSApplication.shared
// `.accessory` plus LSUIElement makes this a menu bar item with no Dock icon.
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
application.run()
