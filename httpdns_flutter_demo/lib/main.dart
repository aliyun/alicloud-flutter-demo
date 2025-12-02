import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'net/httpdns_http_client_adapter.dart';
import 'package:aliyun_httpdns/aliyun_httpdns.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HTTP Request Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'HTTP Request Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

enum NetworkLibrary {
  dio('Dio'),
  httpClient('HttpClient'),
  httpPackage('http');

  const NetworkLibrary(this.displayName);
  final String displayName;
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _urlController = TextEditingController();
  String _responseText = 'Response will appear here...';
  bool _isLoading = false;

  late final Dio _dio;
  late final HttpClient _httpClient;
  late final http.Client _httpPackageClient;

  NetworkLibrary _selectedLibrary = NetworkLibrary.dio;

  bool _httpdnsReady = false;
  bool _httpdnsIniting = false;

  Future<void> _initHttpDnsOnce() async {
    if (_httpdnsReady || _httpdnsIniting) return;
    _httpdnsIniting = true;
    try {
      await AliyunHttpdns.init(
        accountId: 000000, // 请替换为您的 Account ID
        secretKey: 'your_secret_key_here', // 请替换为您的 Secret Key
      );
      await AliyunHttpdns.setHttpsRequestEnabled(true);
      await AliyunHttpdns.setLogEnabled(true);
      await AliyunHttpdns.setPersistentCacheIPEnabled(true);
      await AliyunHttpdns.setReuseExpiredIPEnabled(true);
      
      // 设置 IP 优选列表（在 build 之前）
      await AliyunHttpdns.setIPRankingList({
        'www.aliyun.com': 443,
        'www.taobao.com': 443,
      });
      debugPrint('[httpdns] IP ranking list configured');
      
      await AliyunHttpdns.build();

      // 先build再执行解析相关动作
      final preResolveHosts = 'www.aliyun.com';
      await AliyunHttpdns.setPreResolveHosts([preResolveHosts], ipType: 'both');
      debugPrint('[httpdns] pre-resolve scheduled for host=$preResolveHosts');
      _httpdnsReady = true;
    } catch (e) {
      debugPrint('[httpdns] init failed: $e');
    } finally {
      _httpdnsIniting = false;
    }
  }

  @override
  void initState() {
    super.initState();
    // 设置默认的API URL用于演示
    _urlController.text = 'https://www.aliyun.com';

    // 仅首次进入页面时初始化 HTTPDNS
    _initHttpDnsOnce();

    // 先初始化HTTPDNS再初始化Dio
    _dio = Dio();
    _dio.httpClientAdapter = buildHttpdnsHttpClientAdapter();
    _dio.options.headers['Connection'] = 'keep-alive';

    _httpClient = buildHttpdnsNativeHttpClient();
    _httpPackageClient = buildHttpdnsHttpPackageClient();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _httpClient.close();
    _httpPackageClient.close();
    super.dispose();
  }

  Future<void> _sendHttpRequest() async {
    if (_urlController.text.isEmpty) {
      setState(() {
        _responseText = 'Error: Please enter a URL';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _responseText = 'Sending request...';
    });

    final uri = Uri.parse(_urlController.text);

    try {
      final String libraryName = _selectedLibrary.displayName;
      debugPrint('[$libraryName] Sending request to ${uri.host}:${uri.port}');

      int statusCode;
      Map<String, String> headers;
      String body;

      switch (_selectedLibrary) {
        case NetworkLibrary.dio:
          final response = await _dio.getUri(
            uri,
            options: Options(
              responseType: ResponseType.plain,
              followRedirects: true,
              validateStatus: (_) => true,
            ),
          );
          statusCode = response.statusCode ?? 0;
          headers = {
            for (final e in response.headers.map.entries)
              e.key: e.value.join(','),
          };
          body = response.data is String
              ? response.data as String
              : jsonEncode(response.data);
          break;

        case NetworkLibrary.httpClient:
          final request = await _httpClient.getUrl(uri);
          final response = await request.close();
          statusCode = response.statusCode;
          headers = {};
          response.headers.forEach((name, values) {
            headers[name] = values.join(',');
          });
          body = await response.transform(utf8.decoder).join();
          break;

        case NetworkLibrary.httpPackage:
          final response = await _httpPackageClient.get(uri);
          statusCode = response.statusCode;
          headers = response.headers;
          body = response.body;
          break;
      }

      setState(() {
        _isLoading = false;

        final StringBuffer responseInfo = StringBuffer();

        responseInfo.writeln('=== REQUEST ($libraryName) ===');
        responseInfo.writeln('uri: ${uri.toString()}');
        responseInfo.writeln();

        responseInfo.writeln('=== STATUS ===');
        responseInfo.writeln('statusCode: $statusCode');
        responseInfo.writeln();

        responseInfo.writeln('=== HEADERS ===');
        headers.forEach((key, value) {
          responseInfo.writeln('$key: $value');
        });
        responseInfo.writeln();

        responseInfo.writeln('=== BODY ===');
        if (statusCode >= 200 && statusCode < 300) {
          try {
            final jsonData = json.decode(body);
            const encoder = JsonEncoder.withIndent('  ');
            responseInfo.write(encoder.convert(jsonData));
          } catch (_) {
            responseInfo.write(body);
          }
        } else {
          responseInfo.write(body);
        }

        _responseText = responseInfo.toString();
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _responseText = 'Network Error: $e';
      });
    }
  }

  // 使用 HTTPDNS 解析当前 URL 的 host 并显示结果
  Future<void> _testHttpDnsResolve() async {
    final text = _urlController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _responseText = 'Error: Please enter a URL';
      });
      return;
    }

    final Uri uri;
    try {
      uri = Uri.parse(text);
    } catch (_) {
      setState(() {
        _responseText = 'Error: Invalid URL';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _responseText = 'Resolving with HTTPDNS...';
    });

    try {
      // 确保只初始化一次
      await _initHttpDnsOnce();
      final res = await AliyunHttpdns.resolveHostSyncNonBlocking(
        uri.host,
        ipType: 'both',
      );
      setState(() {
        _isLoading = false;
        final buf = StringBuffer();
        buf.writeln('=== HTTPDNS RESOLVE ===');
        buf.writeln('host: ${uri.host}');
        final ipv4 = (res['ipv4'] as List?)?.cast<String>() ?? const <String>[];
        final ipv6 = (res['ipv6'] as List?)?.cast<String>() ?? const <String>[];
        if (ipv4.isNotEmpty) buf.writeln('IPv4 list: ${ipv4.join(', ')}');
        if (ipv6.isNotEmpty) buf.writeln('IPv6 list: ${ipv6.join(', ')}');
        _responseText = buf.toString();
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _responseText = 'HTTPDNS Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // URL输入框
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Enter URL',
                hintText: 'https://www.aliyun.com',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _sendHttpRequest,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(_isLoading ? 'Sending...' : 'Send Request'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<NetworkLibrary>(
                      value: _selectedLibrary,
                      isExpanded: true,
                      underline: const SizedBox(),
                      icon: const Icon(Icons.arrow_drop_down),
                      items: NetworkLibrary.values.map((library) {
                        return DropdownMenuItem<NetworkLibrary>(
                          value: library,
                          child: Text(library.displayName),
                        );
                      }).toList(),
                      onChanged: _isLoading
                          ? null
                          : (NetworkLibrary? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _selectedLibrary = newValue;
                                });
                              }
                            },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // HTTPDNS 解析按钮
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testHttpDnsResolve,
              icon: const Icon(Icons.dns),
              label: const Text('HTTPDNS Resolve'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 16),

            // 保留空白分隔
            const SizedBox(height: 16),

            // 响应文本显示区域
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade50,
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _responseText,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
