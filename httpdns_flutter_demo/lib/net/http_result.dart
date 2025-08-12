import 'dart:collection';

class HttpResponseInfo {
  final Uri uri;
  final int statusCode;
  final String? statusMessage;
  final Map<String, String> headers;
  final String body;

  // Connection details
  final String? remoteIp;
  final int? remotePort;
  final bool usedProxy;
  final String? proxyHost;
  final int? proxyPort;
  final String? alpnProtocol; // h2 / http/1.1 when available

  const HttpResponseInfo({
    required this.uri,
    required this.statusCode,
    required this.statusMessage,
    required this.headers,
    required this.body,
    this.remoteIp,
    this.remotePort,
    this.usedProxy = false,
    this.proxyHost,
    this.proxyPort,
    this.alpnProtocol,
  });

  Map<String, String> get normalizedHeaders => UnmodifiableMapView(headers);
}


