import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Files and magnet links opened with this app: "Open With" or a
  // double-click in Finder, a magnet link in a browser (see Info.plist). When
  // one starts the app, it arrives before Dart runs, so it is queued.
  override func application(_ application: NSApplication, open urls: [URL]) {
    OpenRequestBridge.shared.add(urls.map { $0.isFileURL ? $0.path : $0.absoluteString })
  }
}

/// Hands the files and links the app was asked to open to Dart over the
/// "convert_the_spire/open" channel. Dart takes the queue with takePending
/// when it starts and whenever "pending" says more arrived.
final class OpenRequestBridge {
  static let shared = OpenRequestBridge()

  private var pending: [String] = []
  private var channel: FlutterMethodChannel?

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "convert_the_spire/open", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "takePending" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.pending ?? [])
      self?.pending.removeAll()
    }
    self.channel = channel
  }

  func add(_ targets: [String]) {
    pending.append(contentsOf: targets)
    channel?.invokeMethod("pending", arguments: nil)
  }
}
