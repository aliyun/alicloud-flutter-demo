import 'dart:async';
import 'package:flutter/services.dart';

class AliyunHttpdns {
  static const MethodChannel _channel = MethodChannel('aliyun_httpdns');

  /// 1) 初始化：使用 accountId/secretKey/aesSecretKey
  static Future<bool> init({
    required int accountId,
    String? secretKey,
    String? aesSecretKey,
  }) async {
    final ok =
        await _channel.invokeMethod<bool>('initialize', <String, dynamic>{
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

  /// 2) 设置日志开关
  static Future<void> setLogEnabled(bool enabled) async {
    await _channel.invokeMethod<void>('setLogEnabled', <String, dynamic>{
      'enabled': enabled,
    });
  }

  /// 3) 设置持久化缓存
  static Future<void> setPersistentCacheIPEnabled(bool enabled,
      {int? discardExpiredAfterSeconds}) async {
    await _channel
        .invokeMethod<void>('setPersistentCacheIPEnabled', <String, dynamic>{
      'enabled': enabled,
      if (discardExpiredAfterSeconds != null)
        'discardExpiredAfterSeconds': discardExpiredAfterSeconds,
    });
  }

  /// 4) 是否允许复用过期 IP
  static Future<void> setReuseExpiredIPEnabled(bool enabled) async {
    await _channel
        .invokeMethod<void>('setReuseExpiredIPEnabled', <String, dynamic>{
      'enabled': enabled,
    });
  }

  /// 设置是否使用 HTTPS 解析链路，避免明文流量被系统拦截
  static Future<void> setHttpsRequestEnabled(bool enabled) async {
    await _channel
        .invokeMethod<void>('setHttpsRequestEnabled', <String, dynamic>{
      'enabled': enabled,
    });
  }

  /// 5) 伪异步解析：返回 IPv4/IPv6 数组
  /// 返回格式：{"ipv4": `List<String>`, "ipv6": `List<String>`}
  static Future<Map<String, List<String>>> resolveHostSyncNonBlocking(
    String hostname, {
    String ipType = 'auto', // auto/ipv4/ipv6/both
    Map<String, String>? sdnsParams,
    String? cacheKey,
  }) async {
    final Map<dynamic, dynamic>? res = await _channel
        .invokeMethod('resolveHostSyncNonBlocking', <String, dynamic>{
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
  static Future<Map<String, dynamic>?> resolve(String hostname,
      {Map<String, dynamic>? options}) async {
    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('resolve', {
      'hostname': hostname,
      if (options != null) 'options': options,
    });
    return res?.map((key, value) => MapEntry(key.toString(), value));
  }

  // 1) setPreResolveHosts: 传入 host 列表，native 侧调用 SDK 预解析
  static Future<void> setPreResolveHosts(List<String> hosts,
      {String ipType = 'auto'}) async {
    await _channel.invokeMethod<void>('setPreResolveHosts', <String, dynamic>{
      'hosts': hosts,
      'ipType': ipType,
    });
  }

  // 2) setLogEnabled: 已有，同步保留（在此文件顶部已有 setLogEnabled 实现）

  // 3) setPreResolveAfterNetworkChanged: 是否在网络切换时自动刷新解析
  static Future<void> setPreResolveAfterNetworkChanged(bool enabled) async {
    await _channel.invokeMethod<void>(
        'setPreResolveAfterNetworkChanged', <String, dynamic>{
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
  
  /// 设置 IP 优选列表
  /// [hostPortMap] 域名和端口的映射，例如：{'www.aliyun.com': 443}
  static Future<void> setIPRankingList(Map<String, int> hostPortMap) async {
    await _channel.invokeMethod<void>('setIPRankingList', <String, dynamic>{
      'hostPortMap': hostPortMap,
    });
  }
}
