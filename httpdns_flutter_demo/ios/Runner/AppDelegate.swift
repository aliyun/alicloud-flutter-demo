import Flutter
import UIKit
import SystemConfiguration
import CFNetwork

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "system_proxy", binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getProxyForUrl" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard let args = call.arguments as? [String: Any], let urlString = args["url"] as? String, let url = URL(string: urlString) else {
        NSLog("SystemProxy: url argument is missing or invalid")
        result(nil)
        return
      }

      // 使用 CFNetworkCopySystemProxySettings 与 CFNetworkCopyProxiesForURL 解析系统代理
      let settingsDict: [String: Any] = (CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any]) ?? [:]
      let cfProxies = CFNetworkCopyProxiesForURL(url as CFURL, settingsDict as CFDictionary).takeRetainedValue() as NSArray

      guard let first = cfProxies.firstObject as? [String: Any] else {
        NSLog("SystemProxy: No proxy settings for URL: \(urlString)")
        result(nil)
        return
      }

      if let type = first[kCFProxyTypeKey as String] as? String {
        if type == (kCFProxyTypeNone as String) {
          NSLog("SystemProxy: Using DIRECT for URL: \(urlString)")
          result("DIRECT")
          return
        }

        let host = first[kCFProxyHostNameKey as String] as? String ?? ""
        let portNum = first[kCFProxyPortNumberKey as String] as? NSNumber
        let port = portNum?.intValue ?? 0

        if type == (kCFProxyTypeHTTP as String) || type == (kCFProxyTypeHTTPS as String) {
          let value = "PROXY \(host):\(port)"
          NSLog("SystemProxy: Resolved HTTP(S) proxy for URL: \(urlString) -> \(value)")
          result(value)
          return
        } else if type == (kCFProxyTypeSOCKS as String) {
          let value = "SOCKS \(host):\(port)"
          NSLog("SystemProxy: Resolved SOCKS proxy for URL: \(urlString) -> \(value)")
          result(value)
          return
        } else if type == (kCFProxyTypeAutoConfigurationURL as String) || type == (kCFProxyTypeAutoConfigurationJavaScript as String) {
          // 对 PAC 场景，不在此同步执行 PAC 脚本，保持简单返回空
          NSLog("SystemProxy: PAC configuration detected; not evaluating synchronously")
          result(nil)
          return
        }
      }

      result(nil)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
