import Cocoa
import FlutterMacOS
import window_manager
import LaunchAtLogin

class MainFlutterWindow: NSWindow {
    static let proxyAuthorization = FengWoProxyAuthorization()

    override func awakeFromNib() {
        let flutterViewController = FlutterViewController()
        let windowFrame = self.frame
        self.contentViewController = flutterViewController
        self.setFrame(windowFrame, display: true)
        
        FlutterMethodChannel(
            name: "launch_at_startup", binaryMessenger: flutterViewController.engine.binaryMessenger
        )
        .setMethodCallHandler { (_ call: FlutterMethodCall, result: @escaping FlutterResult) in
            switch call.method {
            case "launchAtStartupIsEnabled":
                result(LaunchAtLogin.isEnabled)
            case "launchAtStartupSetEnabled":
                if let arguments = call.arguments as? [String: Any] {
                    LaunchAtLogin.isEnabled = arguments["setEnabledValue"] as! Bool
                }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        
        FlutterMethodChannel(
            name: "com.fengwo.accelerator/identity",
            binaryMessenger: flutterViewController.engine.binaryMessenger
        ).setMethodCallHandler { call, result in
            guard call.method == "prepareIdentity" else {
                result(FlutterMethodNotImplemented)
                return
            }
            do {
                result(try FengWoIdentityMigration.production().prepare().dictionary)
            } catch {
                result(["legacyImported": false, "status": "migration_failed"])
            }
        }

        let proxyAuthorizationChannel = FlutterMethodChannel(
            name: "com.fengwo.accelerator/proxy_authorization",
            binaryMessenger: flutterViewController.engine.binaryMessenger
        )
        Self.proxyAuthorization.onProgress = { event, fields in
            DispatchQueue.main.async {
                proxyAuthorizationChannel.invokeMethod("diagnostic", arguments: ["event": event, "fields": fields])
            }
        }
        proxyAuthorizationChannel.setMethodCallHandler { call, result in
            Self.proxyAuthorization.handle(method: call.method, arguments: call.arguments) { response in
                if let response { result(response) }
                else { result(FlutterMethodNotImplemented) }
            }
        }

        RegisterGeneratedPlugins(registry: flutterViewController)
        super.awakeFromNib()
    }
    override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        hiddenWindowAtLaunch()
    }
}
