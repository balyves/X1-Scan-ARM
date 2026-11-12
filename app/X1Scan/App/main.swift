// SPDX-License-Identifier: MIT
import AppKit

// No storyboard: the menu bar and the window are built in code.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
