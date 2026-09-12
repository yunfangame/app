import Cocoa
import FlutterMacOS

public class WindowExtPlugin: NSObject, FlutterPlugin {
    public static var instance: WindowExtPlugin?
    public private(set) var terminateHandlerReady = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "window_ext", binaryMessenger: registrar.messenger)
        instance = WindowExtPlugin(registrar, channel)
        registrar.addMethodCallDelegate(instance!, channel: channel)
    }

    private var registrar: FlutterPluginRegistrar!
    private var channel: FlutterMethodChannel!

    public init(_ registrar: FlutterPluginRegistrar, _ channel: FlutterMethodChannel) {
        super.init()
        self.registrar = registrar
        self.channel = channel
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setTerminateHandlerReady":
            let arguments = call.arguments as? [String: Any]
            terminateHandlerReady = arguments?["ready"] as? Bool ?? false
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    @discardableResult
    public func handleShouldTerminate() -> Bool {
        guard terminateHandlerReady else {
            return false
        }
        channel.invokeMethod("shouldTerminate", arguments: nil)
        return true
    }

    @discardableResult
    public func handleReopen() -> Bool {
        guard terminateHandlerReady else {
            return false
        }
        channel.invokeMethod("reopen", arguments: nil)
        return true
    }
}
