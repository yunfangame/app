import Cocoa
import FlutterMacOS
import window_ext

@main
class AppDelegate: FlutterAppDelegate {
    private var terminationReplyPending = false
    
    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard WindowExtPlugin.instance?.handleShouldTerminate() == true else {
            return .terminateNow
        }
        if !terminationReplyPending {
            terminationReplyPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
      return true
    }
    
    override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if WindowExtPlugin.instance?.handleReopen() == true {
            return false
        }
        if !flag {
            if let window = NSApp.windows.first(where: { $0.contentViewController is FlutterViewController }) {
                window.setIsVisible(true)
                window.makeKeyAndOrderFront(self)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        return true
    }
}
