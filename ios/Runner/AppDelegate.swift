// SPDX-License-Identifier: AGPL-3.0-or-later
import Flutter
import UIKit
import WebKit
import webview_flutter_wkwebview

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var downloads: [Int64: DashboardDownloads] = [:]

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    excludeConnectionDataFromBackup()
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AstrBotMobileWebFiles")
    else { return }
    let channel = FlutterMethodChannel(
      name: "app.astrbotmobile/web_files", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self, let args = call.arguments as? [String: Any],
            let id = (args["id"] as? NSNumber)?.int64Value else {
        result(FlutterError(code: "invalid_args", message: nil, details: nil))
        return
      }
      switch call.method {
      case "attach":
        guard let port = args["port"] as? Int,
              let view = FWFWebViewFlutterWKWebViewExternalAPI.webView(
                forIdentifier: id, withPluginRegistrar: registrar),
              let delegate = view.navigationDelegate else {
          result(FlutterError(code: "missing_webview", message: nil, details: nil))
          return
        }
        if self.downloads[id] == nil {
          let bridge = DashboardDownloads(view: view, original: delegate, port: port)
          self.downloads[id] = bridge
          view.navigationDelegate = bridge
        }
        result(nil)
      case "detach":
        self.downloads.removeValue(forKey: id)?.detach()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func excludeConnectionDataFromBackup() {
    let manager = FileManager.default
    guard let library = manager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
      return
    }
    for name in ["Preferences", "WebKit"] {
      var directory = library.appendingPathComponent(name, isDirectory: true)
      try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
      var resources = URLResourceValues()
      resources.isExcludedFromBackup = true
      try? directory.setResourceValues(resources)
    }
  }
}

@MainActor
private final class DashboardDownloads: NSObject, WKNavigationDelegate, WKDownloadDelegate,
    UIDocumentPickerDelegate {
  private weak var view: WKWebView?
  private nonisolated(unsafe) let original: WKNavigationDelegate
  private let port: Int
  private var download: WKDownload?
  private var folder: URL?
  private var file: URL?
  private weak var picker: UIDocumentPickerViewController?
  private var detached = false

  init(view: WKWebView, original: WKNavigationDelegate, port: Int) {
    self.view = view
    self.original = original
    self.port = port
  }

  // Forward the plugin's navigation lifecycle, errors and authentication callbacks.
  override nonisolated func responds(to selector: Selector!) -> Bool {
    super.responds(to: selector) || original.responds(to: selector)
  }

  override nonisolated func forwardingTarget(for selector: Selector!) -> Any? {
    original.responds(to: selector) ? original : super.forwardingTarget(for: selector)
  }

  private func isDashboard(_ url: URL?, allowBlob: Bool = false) -> Bool {
    guard let url else { return false }
    if allowBlob && url.scheme == "blob" {
      return url.absoluteString.hasPrefix("blob:http://127.0.0.1:\(port)/")
    }
    return url.scheme == "http" && url.host == "127.0.0.1" && url.port == port
      && url.user == nil && url.password == nil
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
    preferences: WKWebpagePreferences,
    decisionHandler: @escaping @MainActor @Sendable
      (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
  ) {
    if action.shouldPerformDownload {
      decisionHandler(
        isDashboard(action.request.url, allowBlob: true) && isDashboard(webView.url)
          ? .download : .cancel, preferences)
      return
    }
    if original.webView?(webView, decidePolicyFor: action, preferences: preferences,
                         decisionHandler: decisionHandler) != nil { return }
    if original.webView?(webView, decidePolicyFor: action,
                         decisionHandler: { decisionHandler($0, preferences) }) != nil { return }
    decisionHandler(.cancel, preferences)
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
    decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
  ) {
    let disposition = (response.response as? HTTPURLResponse)?
      .value(forHTTPHeaderField: "Content-Disposition")?.lowercased()
    if disposition?.hasPrefix("attachment") == true ||
        (response.isForMainFrame && !response.canShowMIMEType) {
      decisionHandler(isDashboard(response.response.url) ? .download : .cancel)
      return
    }
    if original.webView?(webView, decidePolicyFor: response,
                         decisionHandler: decisionHandler) != nil { return }
    decisionHandler(.cancel)
  }

  func webView(_ webView: WKWebView, navigationAction: WKNavigationAction,
               didBecome download: WKDownload) {
    begin(download)
  }

  func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse,
               didBecome download: WKDownload) {
    begin(download)
  }

  private func begin(_ task: WKDownload) {
    guard !detached, download == nil, picker == nil else {
      task.cancel(nil)
      return
    }
    download = task
    task.delegate = self
  }

  func download(
    _ download: WKDownload, decideDestinationUsing response: URLResponse,
    suggestedFilename: String, completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
  ) {
    guard isDashboard(response.url, allowBlob: true), !detached else {
      completionHandler(nil)
      clean()
      return
    }
    let name = String(suggestedFilename
      .components(separatedBy: CharacterSet(charactersIn: "/\\:").union(.controlCharacters))
      .joined(separator: "_").prefix(180))
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("astrbot-export-\(UUID().uuidString)", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
      folder = directory
      let destination = directory.appendingPathComponent(
        ["", ".", ".."].contains(name) ? "download" : name)
      file = destination
      completionHandler(destination)
    } catch {
      completionHandler(nil)
      clean()
    }
  }

  func download(
    _ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    decisionHandler: @escaping @MainActor @Sendable (WKDownload.RedirectPolicy) -> Void
  ) {
    decisionHandler(isDashboard(request.url) ? .allow : .cancel)
  }

  func downloadDidFinish(_ download: WKDownload) {
    guard download === self.download, !detached, let file,
          var presenter = view?.window?.rootViewController else {
      clean()
      return
    }
    self.download = nil
    while let presented = presenter.presentedViewController { presenter = presented }
    let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
    picker.delegate = self
    self.picker = picker
    presenter.present(picker, animated: true)
  }

  func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
    if download === self.download { clean() }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    clean()
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    clean()
  }

  func detach() {
    detached = true
    if view?.navigationDelegate === self { view?.navigationDelegate = original }
    download?.cancel(nil)
    picker?.dismiss(animated: false)
    clean()
  }

  private func clean() {
    download = nil
    picker = nil
    file = nil
    if let folder { try? FileManager.default.removeItem(at: folder) }
    folder = nil
  }
}
