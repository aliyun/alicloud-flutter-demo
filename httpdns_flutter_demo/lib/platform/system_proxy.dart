import 'package:flutter/services.dart';

class SystemProxyResolver {
  static const MethodChannel _channel = MethodChannel('system_proxy');

  // 从系统解析当前 URL 的代理规则。返回例如: 'PROXY host:port' 或 'DIRECT' 或 null
  static Future<String?> getProxyRuleForUri(Uri uri) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'getProxyForUrl',
        <String, dynamic>{'url': uri.toString()},
      );
      return result;
    } on PlatformException {
      return null;
    }
  }
}


