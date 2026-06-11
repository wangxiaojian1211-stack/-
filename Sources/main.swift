import AppKit

// Create the application
let app = NSApplication.shared
let delegate = StatusBarController()
app.delegate = delegate

// Set activation policy to accessory (no dock icon)
app.setActivationPolicy(.accessory)

// Run the app
app.run()
