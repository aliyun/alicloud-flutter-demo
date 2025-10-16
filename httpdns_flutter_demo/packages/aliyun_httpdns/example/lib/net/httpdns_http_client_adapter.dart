import 'dart:io';

import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:aliyun_httpdns/aliyun_httpdns.dart';

/* *
 * 构建带 HTTPDNS 能力的 IOHttpClientAdapter
 *
 * 本方案由EMAS团队设计实现，参考请注明出处。
*/

IOHttpClientAdapter buildHttpdnsHttpClientAdapter() {
  final HttpClient client = HttpClient();
  _configureHttpClient(client);

  _configureConnectionFactory(client);

  final IOHttpClientAdapter adapter = IOHttpClientAdapter(
    createHttpClient: () => client,
  )..validateCertificate = (cert, host, port) => true;
  return adapter;
}

HttpClient buildHttpdnsNativeHttpClient() {
  final HttpClient client = HttpClient();
  _configureHttpClient(client);
  _configureConnectionFactory(client);
  return client;
}

http.Client buildHttpdnsHttpPackageClient() {
  final HttpClient httpClient = buildHttpdnsNativeHttpClient();
  return IOClient(httpClient);
}

// HttpClient 基础配置
void _configureHttpClient(HttpClient client) {
  client.findProxy = (Uri _) => 'DIRECT';
  client.idleTimeout = const Duration(seconds: 90);
  client.maxConnectionsPerHost = 8;
}

// 配置基于 HTTPDNS 的连接工厂
void _configureConnectionFactory(HttpClient client) {
  client
      .connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
    final String domain = uri.host;
    final bool https = uri.scheme.toLowerCase() == 'https';
    final int port = uri.port == 0 ? (https ? 443 : 80) : uri.port;

    final List<InternetAddress> targets = await _resolveTargets(domain);
    final Object target = targets.isNotEmpty ? targets.first : domain;

    if (!https) {
      return Socket.startConnect(target, port);
    }

    // HTTPS：先 TCP，再 TLS（SNI=域名），并保持可取消
    bool cancelled = false;
    final Future<ConnectionTask<Socket>> rawStart = Socket.startConnect(
      target,
      port,
    );
    final Future<Socket> upgraded = rawStart.then((task) async {
      final Socket raw = await task.socket;
      if (cancelled) {
        raw.destroy();
        throw const SocketException('Connection cancelled');
      }
      final SecureSocket secure = await SecureSocket.secure(raw, host: domain);
      if (cancelled) {
        secure.destroy();
        throw const SocketException('Connection cancelled');
      }
      return secure;
    });
    return ConnectionTask.fromSocket(upgraded, () {
      cancelled = true;
      try {
        rawStart.then((t) => t.cancel());
      } catch (_) {}
    });
  };
}

// 通过 HTTPDNS 解析目标 IP 列表；IPv4 优先；失败则返回空列表（上层回退系统 DNS）
Future<List<InternetAddress>> _resolveTargets(String domain) async {
  try {
    final res = await AliyunHttpdns.resolveHostSyncNonBlocking(
      domain,
      ipType: 'both',
    );
    final List<String> ipv4 =
        (res['ipv4'] as List?)?.cast<String>() ?? const <String>[];
    final List<String> ipv6 =
        (res['ipv6'] as List?)?.cast<String>() ?? const <String>[];
    final List<InternetAddress> targets = [
      ...ipv4.map(InternetAddress.tryParse).whereType<InternetAddress>(),
      ...ipv6.map(InternetAddress.tryParse).whereType<InternetAddress>(),
    ];
    if (targets.isEmpty) {
      debugPrint('[HTTPDNS] no result for $domain, fallback to system DNS');
    } else {
      debugPrint('[HTTPDNS] resolved $domain -> ${targets.first.address}');
    }
    return targets;
  } catch (e) {
    debugPrint('[HTTPDNS] resolve failed: $e, fallback to system DNS');
    return const <InternetAddress>[];
  }
}
