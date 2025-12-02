import Flutter
import UIKit
import AlicloudHTTPDNS

public class AliyunHttpDnsPlugin: NSObject, FlutterPlugin {
  private var channel: FlutterMethodChannel!

  // Desired states saved until build()
  private var desiredAccountId: Int?
  private var desiredSecretKey: String?
  private var desiredAesSecretKey: String?

  private var desiredPersistentCacheEnabled: Bool?
  private var desiredDiscardExpiredAfterSeconds: Int?
  private var desiredReuseExpiredIPEnabled: Bool?
  private var desiredLogEnabled: Bool?
  private var desiredHttpsEnabled: Bool?
  private var desiredPreResolveAfterNetworkChanged: Bool?
  private var desiredIPRankingMap: [String: NSNumber]?



  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "aliyun_httpdns", binaryMessenger: registrar.messenger())
    let instance = AliyunHttpDnsPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    // Dart: init(accountId, secretKey?, aesSecretKey?) — only save desired state
    case "initialize":
      let options = call.arguments as? [String: Any] ?? [:]
      let accountIdAny = options["accountId"]
      let secretKey = options["secretKey"] as? String
      let aesSecretKey = options["aesSecretKey"] as? String

      guard let accountId = (accountIdAny as? Int) ?? Int((accountIdAny as? String) ?? "") else {
        NSLog("AliyunHttpDns: initialize missing accountId")
        result(false)
        return
      }
      desiredAccountId = accountId
      desiredSecretKey = secretKey
      desiredAesSecretKey = aesSecretKey
      NSLog("AliyunHttpDns: initialize saved accountId=\(accountId)")
      result(true)



    // Dart: setLogEnabled(enabled) — save desired
    case "setLogEnabled":
      let args = call.arguments as? [String: Any]
      let enabled = (args?["enabled"] as? Bool) ?? false
      desiredLogEnabled = enabled
      NSLog("AliyunHttpDns: log desired=\(enabled)")
      result(nil)

    case "setHttpsRequestEnabled":
      let args = call.arguments as? [String: Any]
      let enabled = (args?["enabled"] as? Bool) ?? false
      desiredHttpsEnabled = enabled
      NSLog("AliyunHttpDns: https request desired=\(enabled)")
      result(nil)

    // Dart: setPersistentCacheIPEnabled(enabled, discardExpiredAfterSeconds?) — save desired
    case "setPersistentCacheIPEnabled":
      let args = call.arguments as? [String: Any]
      let enabled = (args?["enabled"] as? Bool) ?? false
      let discard = args?["discardExpiredAfterSeconds"] as? Int
      desiredPersistentCacheEnabled = enabled
      desiredDiscardExpiredAfterSeconds = discard
      NSLog("AliyunHttpDns: persistent cache desired=\(enabled) discard=\(discard ?? -1)")
      result(nil)

    // Dart: setReuseExpiredIPEnabled(enabled) — save desired
    case "setReuseExpiredIPEnabled":
      let args = call.arguments as? [String: Any]
      let enabled = (args?["enabled"] as? Bool) ?? false
      desiredReuseExpiredIPEnabled = enabled
      NSLog("AliyunHttpDns: reuse expired ip desired=\(enabled)")
      result(nil)

    case "setPreResolveAfterNetworkChanged":
      let args = call.arguments as? [String: Any]
      let enabled = (args?["enabled"] as? Bool) ?? false
      desiredPreResolveAfterNetworkChanged = enabled
      NSLog("AliyunHttpDns: preResolveAfterNetworkChanged desired=\(enabled)")
      result(nil)

    case "setIPRankingList":
      let args = call.arguments as? [String: Any]
      let hostPortMap = args?["hostPortMap"] as? [String: NSNumber]
      desiredIPRankingMap = hostPortMap
      NSLog("AliyunHttpDns: IP ranking list desired, hosts=\(hostPortMap?.keys.joined(separator: ", ") ?? "")")
      result(nil)

    case "setPreResolveHosts":
      let args = call.arguments as? [String: Any]
      let hosts = (args?["hosts"] as? [String]) ?? []
      let ipTypeStr = (args?["ipType"] as? String) ?? "auto"
      switch ipTypeStr.lowercased() {
      case "ipv4", "v4":
        HttpDnsService.sharedInstance().setPreResolveHosts(hosts, queryIPType: AlicloudHttpDNS_IPType.init(0))
      case "ipv6", "v6":
        HttpDnsService.sharedInstance().setPreResolveHosts(hosts, queryIPType: AlicloudHttpDNS_IPType.init(1))
      case "both", "64":
        HttpDnsService.sharedInstance().setPreResolveHosts(hosts, queryIPType: AlicloudHttpDNS_IPType.init(2))
      default:
        HttpDnsService.sharedInstance().setPreResolveHosts(hosts)
      }
      result(nil)

    case "getSessionId":
      let sid = HttpDnsService.sharedInstance().getSessionId()
      result(sid)

    case "cleanAllHostCache":
      HttpDnsService.sharedInstance().cleanAllHostCache()
      result(nil)

    // Dart: build() — construct service and apply desired states
    case "build":
      guard let accountId = desiredAccountId else {
        result(false)
        return
      }
      // Initialize singleton
      if let secret = desiredSecretKey, !secret.isEmpty {
        if let aes = desiredAesSecretKey, !aes.isEmpty {
          _ = HttpDnsService(accountID: accountId, secretKey: secret, aesSecretKey: aes)
        } else {
          _ = HttpDnsService(accountID: accountId, secretKey: secret)
        }
      } else {
        _ = HttpDnsService(accountID: accountId) // deprecated but acceptable fallback
      }
      let svc = HttpDnsService.sharedInstance()
      // Apply desired runtime flags
      if let enable = desiredPersistentCacheEnabled {
        if let discard = desiredDiscardExpiredAfterSeconds, discard >= 0 {
          svc.setPersistentCacheIPEnabled(enable, discardRecordsHasExpiredFor: TimeInterval(discard))
        } else {
          svc.setPersistentCacheIPEnabled(enable)
        }
      }
      if let enable = desiredReuseExpiredIPEnabled {
        svc.setReuseExpiredIPEnabled(enable)
      }
      if let enable = desiredLogEnabled {
        svc.setLogEnabled(enable)
      }
      if let enable = desiredHttpsEnabled {
        svc.setHTTPSRequestEnabled(enable)
      }

      if let en = desiredPreResolveAfterNetworkChanged {
        svc.setPreResolveAfterNetworkChanged(en)
      }
      if let ipRankingMap = desiredIPRankingMap, !ipRankingMap.isEmpty {
        svc.setIPRankingDatasource(ipRankingMap)
      }
      NSLog("AliyunHttpDns: build completed accountId=\(accountId)")
      result(true)

    // Dart: resolveHostSyncNonBlocking(hostname, ipType, sdnsParams?, cacheKey?)
    case "resolveHostSyncNonBlocking":
      guard let args = call.arguments as? [String: Any], let host = args["hostname"] as? String else {
        result(["ipv4": [], "ipv6": []])
        return
      }
      let ipTypeStr = (args["ipType"] as? String) ?? "auto"
      let sdnsParams = args["sdnsParams"] as? [String: String]
      let cacheKey = args["cacheKey"] as? String
      let type: HttpdnsQueryIPType
      switch ipTypeStr.lowercased() {
      case "ipv4", "v4": type = .ipv4
      case "ipv6", "v6": type = .ipv6
      case "both", "64": type = .both
      default: type = .auto
      }
      let svc = HttpDnsService.sharedInstance()
      var v4: [String] = []
      var v6: [String] = []
      if let params = sdnsParams, let key = cacheKey, let r = svc.resolveHostSyncNonBlocking(host, by: type, withSdnsParams: params, sdnsCacheKey: key) {
        if r.hasIpv4Address() { v4 = r.ips }
        if r.hasIpv6Address() { v6 = r.ipv6s }
      } else if let r = svc.resolveHostSyncNonBlocking(host, by: type) {
        if r.hasIpv4Address() { v4 = r.ips }
        if r.hasIpv6Address() { v6 = r.ipv6s }
      }
      result(["ipv4": v4, "ipv6": v6])

    // Legacy methods removed: preResolve / clearCache

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}


