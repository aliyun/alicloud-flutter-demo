import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http2/transport.dart';

import 'http_result.dart';
import 'http11.dart';

class _AlpnNotH2 implements Exception {
  final String? negotiated;
  _AlpnNotH2(this.negotiated);
  @override
  String toString() => 'ALPN negotiated ${negotiated ?? 'none'}, not h2';
}

class Http2Client {
  final Duration idleTimeout;
  final Http11Client _fallbackHttp11;

  // Keep a single transport per authority for reuse
  final Map<String, ClientTransportConnection> _authorityToTransport = {};
  final Map<String, SecureSocket> _authorityToSocket = {};
  final Map<String, Timer> _authorityIdleTimers = {};

  Http2Client({this.idleTimeout = const Duration(seconds: 90), Http11Client? fallback})
      : _fallbackHttp11 = fallback ?? Http11Client();

  String _key(Uri uri) => '${uri.host}:${uri.port == 0 ? 443 : uri.port}';

  void _teardown(String key) {
    final transport = _authorityToTransport.remove(key);
    final socket = _authorityToSocket.remove(key);
    _authorityIdleTimers.remove(key)?.cancel();
    if (transport != null) {
      try {
        transport.terminate();
      } catch (_) {
        transport.finish();
      }
    }
    socket?.destroy();
    debugPrint('[http2] teardown $key');
  }

  Future<ClientTransportConnection> _connect(Uri uri) async {
    final authority = _key(uri);
    if (_authorityToTransport.containsKey(authority)) {
      return _authorityToTransport[authority]!;
    }

    final int port = (uri.port == 0) ? 443 : uri.port;
    debugPrint('[http2] TLS connect to ${uri.host}:$port (ALPN h2)');
    final ConnectionTask<SecureSocket> task = await SecureSocket.startConnect(
      uri.host,
      port,
      supportedProtocols: const ['h2', 'http/1.1'],
    );
    final SecureSocket socket = await task.socket;
    debugPrint('[http2] TLS connected remote=${socket.remoteAddress.address}:${socket.remotePort} alpn=${socket.selectedProtocol}');

    if (socket.selectedProtocol != 'h2') {
      // 协商为 HTTP/1.1：把此已握手的 TLS 套接字注入到 HTTP/1.1 客户端供其直接复用
      final keyUri = Uri(scheme: 'https', host: uri.host, port: port);
      _fallbackHttp11.injectHttpsSocket(keyUri, socket);
      throw _AlpnNotH2(socket.selectedProtocol);
    }

    // Create HTTP/2 transport
    final transport = ClientTransportConnection.viaSocket(socket);
    _authorityToTransport[authority] = transport;
    _authorityToSocket[authority] = socket;

    // Basic idle timer to close if unused
    _authorityIdleTimers[authority]?.cancel();
    _authorityIdleTimers[authority] = Timer(idleTimeout, () {
      debugPrint('[http2] idle timeout closing $authority');
      _teardown(authority);
    });

    // Auto-teardown when the socket closes unexpectedly
    socket.done.then((_) {
      if (_authorityToSocket[authority] == socket) {
        debugPrint('[http2] socket done for $authority');
        _teardown(authority);
      }
    }).catchError((_) {
      if (_authorityToSocket[authority] == socket) {
        debugPrint('[http2] socket error/done for $authority');
        _teardown(authority);
      }
    });

    return transport;
  }

  Future<HttpResponseInfo> _getOnce(Uri uri) async {
    final transport = await _connect(uri);

    // Build headers
    final headers = <Header>[
      Header.ascii(':method', 'GET'),
      Header.ascii(':path', uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path.isEmpty ? '/' : uri.path),
      Header.ascii(':scheme', uri.scheme),
      Header.ascii(':authority', uri.hasPort ? '${uri.host}:${uri.port}' : uri.host),
      Header.ascii('accept', 'application/json, text/plain, */*'),
      Header.ascii('user-agent', 'flutter_demo_http2'),
    ];

    final stream = transport.makeRequest(headers, endStream: true);

    int status = 0;
    final responseHeaders = <String, String>{};
    final bodyChunks = <List<int>>[];

    await for (final frame in stream.incomingMessages) {
      if (frame is HeadersStreamMessage) {
        for (final h in frame.headers) {
          final name = ascii.decode(h.name);
          final value = ascii.decode(h.value);
          responseHeaders[name] = value;
          if (name == ':status') {
            status = int.tryParse(value) ?? 0;
          }
        }
      } else if (frame is DataStreamMessage) {
        bodyChunks.add(frame.bytes);
      }
    }

    final body = utf8.decode(bodyChunks.expand((e) => e).toList());
    final socket = _authorityToSocket[_key(uri)];

    return HttpResponseInfo(
      uri: uri,
      statusCode: status,
      statusMessage: null,
      headers: responseHeaders,
      body: body,
      remoteIp: socket?.remoteAddress.address,
      remotePort: socket?.remotePort,
      usedProxy: false,
      proxyHost: null,
      proxyPort: null,
      alpnProtocol: socket?.selectedProtocol,
    );
  }

  Future<HttpResponseInfo> get(Uri uri) async {
    try {
      return await _getOnce(uri);
    } on _AlpnNotH2 catch (e) {
      debugPrint('[http2] ${e.toString()} → falling back to HTTP/1.1');
      return await _fallbackHttp11.get(uri);
    } catch (e) {
      // 出现网络/连接错误时，尝试清理并重连一次
      final key = _key(uri);
      debugPrint('[http2] request error on $key, retrying once: $e');
      _teardown(key);
      try {
        return await _getOnce(uri);
      } catch (e2) {
        debugPrint('[http2] second attempt failed: $e2 → falling back to HTTP/1.1');
        return await _fallbackHttp11.get(uri);
      }
    }
  }

  void close() {
    for (final timer in _authorityIdleTimers.values) {
      timer.cancel();
    }
    _authorityIdleTimers.clear();
    final keys = List<String>.from(_authorityToTransport.keys);
    for (final k in keys) {
      _teardown(k);
    }
  }
}


