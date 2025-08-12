import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import 'http_result.dart';
import '../platform/system_proxy.dart';

class Http11Client {
  final HttpClient _ioHttpClient;
  final Dio _dio;

  // last connection details
  String? lastRemoteIp;
  int? lastRemotePort;
  bool lastUsedProxy = false;
  String? lastProxyHost;
  int? lastProxyPort;
  String? lastAlpnProtocol;

  // 注入的预连接 HTTPS 套接字（用于从 h2 回退到 http/1.1 时重用已有连接）
  final Map<String, SecureSocket> _injectedHttpsSocket = {};

  Http11Client()
      : _ioHttpClient = HttpClient()
          ..findProxy = HttpClient.findProxyFromEnvironment
          ..idleTimeout = const Duration(seconds: 90)
          ..maxConnectionsPerHost = 8,
        _dio = Dio() {
    _ioHttpClient.connectionFactory = (Uri u, String? proxyHost, int? proxyPort) async {
      try {
        // 若存在注入的 HTTPS 套接字，且不经代理，直接复用该套接字
        if (proxyHost == null && proxyPort == null && u.scheme == 'https') {
          final key = _authorityKey(u);
          final injected = _injectedHttpsSocket.remove(key);
          if (injected != null) {
            lastUsedProxy = false;
            lastProxyHost = null;
            lastProxyPort = null;
            lastAlpnProtocol = injected.selectedProtocol;
            lastRemoteIp = injected.remoteAddress.address;
            lastRemotePort = injected.remotePort;
            debugPrint('[http11] Reusing injected TLS socket for $key alpn=${lastAlpnProtocol ?? '(none)'}');
            return ConnectionTask.fromSocket(Future.value(injected), () {});
          }
        }
        if (proxyHost != null && proxyPort != null) {
          lastUsedProxy = true;
          lastProxyHost = proxyHost;
          lastProxyPort = proxyPort;
          debugPrint('[http11] Using proxy $proxyHost:$proxyPort for ${u.scheme.toUpperCase()} ${u.host}:${u.port == 0 ? (u.scheme == 'https' ? 443 : 80) : u.port}');
          final ConnectionTask<Socket> tcpTask = await Socket.startConnect(proxyHost, proxyPort);
          final Socket socket = await tcpTask.socket;
          lastRemoteIp = socket.remoteAddress.address;
          lastRemotePort = socket.remotePort;
          debugPrint('[http11] Connected to proxy remote=$lastRemoteIp:$lastRemotePort');
          lastAlpnProtocol = null;
          return ConnectionTask.fromSocket(Future.value(socket), tcpTask.cancel);
        }

        final int port = (u.port == 0) ? (u.scheme == 'https' ? 443 : 80) : u.port;
        if (u.scheme == 'https') {
          debugPrint('[http11] TLS connect to ${u.host}:$port (ALPN h2/http1.1 allowed)');
          final ConnectionTask<SecureSocket> tlsTask = await SecureSocket.startConnect(
            u.host,
            port,
            supportedProtocols: const ['http/1.1'],
          );
          final SecureSocket socket = await tlsTask.socket;
          lastAlpnProtocol = socket.selectedProtocol;
          lastRemoteIp = socket.remoteAddress.address;
          lastRemotePort = socket.remotePort;
          debugPrint('[http11] TLS connected remote=$lastRemoteIp:$lastRemotePort alpn=${lastAlpnProtocol ?? '(none)'}');
          return ConnectionTask.fromSocket(Future.value(socket), tlsTask.cancel);
        } else {
          debugPrint('[http11] TCP connect to ${u.host}:$port');
          final ConnectionTask<Socket> tcpTask = await Socket.startConnect(u.host, port);
          final Socket socket = await tcpTask.socket;
          lastRemoteIp = socket.remoteAddress.address;
          lastRemotePort = socket.remotePort;
          debugPrint('[http11] TCP connected remote=$lastRemoteIp:$lastRemotePort');
          lastAlpnProtocol = null;
          return ConnectionTask.fromSocket(Future.value(socket), tcpTask.cancel);
        }
      } catch (e) {
        debugPrint('[http11] Failed to build connection: $e');
        rethrow;
      }
    };

    final ioAdapter = IOHttpClientAdapter();
    ioAdapter.createHttpClient = () => _ioHttpClient;
    ioAdapter.validateCertificate = (cert, host, port) => true;
    _dio.httpClientAdapter = ioAdapter;
    _dio.options.headers['Connection'] = 'keep-alive';
  }

  // 将已握手的 HTTPS 套接字注入，供下次连接工厂直接复用
  void injectHttpsSocket(Uri uri, SecureSocket socket) {
    final key = _authorityKey(uri);
    _injectedHttpsSocket[key] = socket;
  }

  String _authorityKey(Uri u) => '${u.host}:${u.port == 0 ? (u.scheme == 'https' ? 443 : 80) : u.port}';

  Future<HttpResponseInfo> get(Uri uri) async {
    // 使用系统代理（iOS Wi-Fi 配置），优先于环境变量
    final rule = await SystemProxyResolver.getProxyRuleForUri(uri);
    if (rule != null && rule.isNotEmpty) {
      _ioHttpClient.findProxy = (_) => rule; // e.g., 'PROXY host:port' or 'DIRECT'
      debugPrint('[http11] findProxy (system): $rule');
    } else {
      _ioHttpClient.findProxy = HttpClient.findProxyFromEnvironment;
      debugPrint('[http11] findProxy (env)');
    }

    final response = await _dio.getUri(uri,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (_) => true,
        ));

    final headers = <String, String>{
      for (final e in response.headers.map.entries) e.key: e.value.join(',')
    };

    return HttpResponseInfo(
      uri: uri,
      statusCode: response.statusCode ?? 0,
      statusMessage: response.statusMessage,
      headers: headers,
      body: response.data is String ? response.data as String : jsonEncode(response.data),
      remoteIp: lastRemoteIp,
      remotePort: lastRemotePort,
      usedProxy: lastUsedProxy,
      proxyHost: lastProxyHost,
      proxyPort: lastProxyPort,
      alpnProtocol: lastAlpnProtocol,
    );
  }
}


