import 'dart:async';
import 'package:flutter/services.dart';

class HttpdnsPlugin {
  static const MethodChannel _channel = MethodChannel('httpdns_plugin');

  /// Dart 侧的 TTL 回调；当 native 侧需要自定义 TTL 时回调到此处
  /// 回调签名：返回应使用的 TTL（单位：秒）
  static int Function(String host, String ipType, int ttl)? _ttlDelegate;

  /// 为了让 native 能够回调 Dart 侧计算 TTL，这里注册一个 handler
  /// 仅处理 TTL 相关的回调，不影响其它 method 的常规调用
  static void _ensureMethodHandlerInstalled() {
    // 只设置一次
    if (_methodHandlerInstalled) return;
    _methodHandlerInstalled = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'ttl#compute') {
        // 约定参数：{ host: string, ipType: string, ttl: int }
        final Map<dynamic, dynamic> args = (call.arguments as Map?) ?? const {};
        final host = args['host']?.toString() ?? '';
        final ipType = args['ipType']?.toString() ?? 'auto';
        final ttl = (args['ttl'] is int) ? args['ttl'] as int : int.tryParse('${args['ttl']}') ?? 0;
        final cb = _ttlDelegate;
        if (cb != null) {
          final nextTtl = cb(host, ipType, ttl);
          return nextTtl;
        }
        return ttl; // 未设置回调则直接透传
      }
      return null;
    });
  }

  static bool _methodHandlerInstalled = false;

  /// 1) 初始化：使用 accountId/secretKey/aesSecretKey
  static Future<bool> init({
    required int accountId,
    String? secretKey,
    String? aesSecretKey,
  }) async {
    final ok = await _channel.invokeMethod<bool>('initialize', <String, dynamic>{
      'accountId': accountId,
      if (secretKey != null) 'secretKey': secretKey,
      if (aesSecretKey != null) 'aesSecretKey': aesSecretKey,
    });
    return ok ?? false;
  }

  /// 构建底层 service，只有在调用了 initialize / 一系列 setXxx 后，
  /// 调用本方法才会真正创建底层实例并应用配置
  static Future<bool> build() async {
    final ok = await _channel.invokeMethod<bool>('build');
    return ok ?? false;
  }

  /// 2) 设置 TTL 委托（回调），用于按域名/类型自定义 TTL
  static Future<void> setTtlDelegate(int Function(String host, String ipType, int ttl)? delegate) async {
    _ttlDelegate = delegate;
    _ensureMethodHandlerInstalled();
    await _channel.invokeMethod<void>('setTtlDelegateEnabled', <String, dynamic>{
      'enabled': delegate != null,
    });
  }

  /// 3) 设置日志开关
  static Future<void> setLogEnabled(bool enabled) async {
    await _channel.invokeMethod<void>('setLogEnabled', <String, dynamic>{
      'enabled': enabled,
    });
  }

  /// 4) 设置持久化缓存
  /// iOS 侧支持带过期丢弃阈值；Android 侧可忽略该可选参数
  static Future<void> setPersistentCacheIPEnabled(bool enabled, {int? discardExpiredAfterSeconds}) async {
    await _channel.invokeMethod<void>('setPersistentCacheIPEnabled', <String, dynamic>{
      'enabled': enabled,
      if (discardExpiredAfterSeconds != null) 'discardExpiredAfterSeconds': discardExpiredAfterSeconds,
    });
  }

  /// 5) 是否允许复用过期 IP
  static Future<void> setReuseExpiredIPEnabled(bool enabled) async {
    await _channel.invokeMethod<void>('setReuseExpiredIPEnabled', <String, dynamic>{
      'enabled': enabled,
    });
  }

  /// 设置是否使用 HTTPS 解析链路，避免明文流量被系统拦截
  static Future<void> setHttpsRequestEnabled(bool enabled) async {
    await _channel.invokeMethod<void>('setHttpsRequestEnabled', <String, dynamic>{
      'enabled': enabled,
    });
  }

  /// 6) 伪异步解析：返回 IPv4/IPv6 数组
  /// 返回格式：{"ipv4": List<String>, "ipv6": List<String>}
  static Future<Map<String, List<String>>> resolveHostSyncNonBlocking(
    String hostname, {
    String ipType = 'auto', // auto/ipv4/ipv6/both
    Map<String, String>? sdnsParams,
    String? cacheKey,
  }) async {
    final Map<dynamic, dynamic>? res = await _channel.invokeMethod('resolveHostSyncNonBlocking', <String, dynamic>{
      'hostname': hostname,
      'ipType': ipType,
      if (sdnsParams != null) 'sdnsParams': sdnsParams,
      if (cacheKey != null) 'cacheKey': cacheKey,
    });
    final Map<String, List<String>> out = {
      'ipv4': <String>[],
      'ipv6': <String>[],
    };
    if (res == null) return out;
    final v4 = res['ipv4'];
    final v6 = res['ipv6'];
    if (v4 is List) {
      out['ipv4'] = v4.map((e) => e.toString()).toList();
    }
    if (v6 is List) {
      out['ipv6'] = v6.map((e) => e.toString()).toList();
    }
    return out;
  }

  // 解析域名，返回 A/AAAA 记录等（保留旧接口以兼容，未在本任务使用）
  static Future<Map<String, dynamic>?> resolve(String hostname, {Map<String, dynamic>? options}) async {
    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('resolve', {
      'hostname': hostname,
      if (options != null) 'options': options,
    });
    return res?.map((key, value) => MapEntry(key.toString(), value));
  }

  // 1) setPreResolveHosts: 传入 host 列表，native 侧调用 SDK 预解析
  static Future<void> setPreResolveHosts(List<String> hosts, {String ipType = 'auto'}) async {
    await _channel.invokeMethod<void>('setPreResolveHosts', <String, dynamic>{
      'hosts': hosts,
      'ipType': ipType,
    });
  }

  // 2) setLogEnabled: 已有，同步保留（在此文件顶部已有 setLogEnabled 实现）

  // 3) setPreResolveAfterNetworkChanged: 是否在网络切换时自动刷新解析
  static Future<void> setPreResolveAfterNetworkChanged(bool enabled) async {
    await _channel.invokeMethod<void>('setPreResolveAfterNetworkChanged', <String, dynamic>{
      'enabled': enabled,
    });
  }

  // 4) getSessionId: 获取会话 id
  static Future<String?> getSessionId() async {
    final sid = await _channel.invokeMethod<String>('getSessionId');
    return sid;
  }

  // 5) cleanAllHostCache: 清除所有缓存
  static Future<void> cleanAllHostCache() async {
    await _channel.invokeMethod<void>('cleanAllHostCache');
  }
}


