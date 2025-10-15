import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'dart:convert';
import 'dart:io';
import 'net/httpdns_http_client_adapter.dart';
import 'package:httpdns_plugin/httpdns_plugin.dart';

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
  httpClient('HttpClient');

  const NetworkLibrary(this.displayName);
  final String displayName;
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _urlController = TextEditingController();
  String _responseText = 'Response will appear here...';
  bool _isLoading = false;

  // 仅保留 Dio 客户端
  late final Dio _dio;
  late final HttpClient _httpClient;

  NetworkLibrary _selectedLibrary = NetworkLibrary.dio;

  bool _httpdnsReady = false;
  bool _httpdnsIniting = false;

  Future<void> _initHttpDnsOnce() async {
    if (_httpdnsReady || _httpdnsIniting) return;
    _httpdnsIniting = true;
    try {
      await HttpdnsPlugin.init(
        accountId: 139450,
        secretKey: '807a19762f8eaefa8563489baf198535',
      );
      await HttpdnsPlugin.setHttpsRequestEnabled(true);
      await HttpdnsPlugin.setLogEnabled(true);
      await HttpdnsPlugin.setPersistentCacheIPEnabled(true);
      await HttpdnsPlugin.setReuseExpiredIPEnabled(true);
      await HttpdnsPlugin.build();

      // 先build再执行解析相关动作
      final preResolveHosts = 'www.aliyun.com';
      await HttpdnsPlugin.setPreResolveHosts([preResolveHosts], ipType: 'both');
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
  }

  @override
  void dispose() {
    _urlController.dispose();
    _httpClient.close();
    super.dispose();
  }

  Future<void> _sendHttpRequest() async {
    switch (_selectedLibrary) {
      case NetworkLibrary.dio:
        await _sendRequestWithDio();
        break;
      case NetworkLibrary.httpClient:
        await _sendRequestWithHttpClient();
        break;
    }
  }

  Future<void> _sendRequestWithDio() async {
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
      debugPrint('[Dio] Sending request to ${uri.host}:${uri.port}');
      final response = await _dio.getUri(
        uri,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (_) => true,
        ),
      );

      final headers = <String, String>{
        for (final e in response.headers.map.entries) e.key: e.value.join(',')
      };
      final Map<String, dynamic> res = {
        'uri': uri.toString(),
        'statusCode': response.statusCode ?? 0,
        'headers': headers,
        'body': response.data is String ? response.data as String : jsonEncode(response.data),
      };

      setState(() {
        _isLoading = false;

        // 构建响应信息字符串
        final StringBuffer responseInfo = StringBuffer();

        // 仅显示基本信息：URI / 状态码 / 响应头 / 响应体
        responseInfo.writeln('=== REQUEST (Dio) ===');
        responseInfo.writeln('uri: ${res['uri']}');
        responseInfo.writeln();

        responseInfo.writeln('=== STATUS ===');
        final int code = (res['statusCode'] as int?) ?? 0;
        responseInfo.writeln('statusCode: $code');
        responseInfo.writeln();

        responseInfo.writeln('=== HEADERS ===');
        final Map<String, dynamic> headersMapDyn = (res['headers'] as Map?)?.cast<String, dynamic>() ?? {};
        headersMapDyn.forEach((key, value) {
          responseInfo.writeln('$key: $value');
        });
        responseInfo.writeln();

        responseInfo.writeln('=== BODY ===');
        final String bodyStr = (res['body'] as String?) ?? '';
        if (code >= 200 && code < 300) {
          try {
            final jsonData = json.decode(bodyStr);
            const encoder = JsonEncoder.withIndent('  ');
            responseInfo.write(encoder.convert(jsonData));
          } catch (_) {
            responseInfo.write(bodyStr);
          }
        } else {
          responseInfo.write(bodyStr);
        }

        _responseText = responseInfo.toString();
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _responseText = 'Network Error: $e';
      });
    } finally {
      // 关闭自定义客户端，避免连接泄漏
      // 不关闭全局客户端，以便保持连接并复用
    }
  }

  // 使用原生 HttpClient 发送请求
  Future<void> _sendRequestWithHttpClient() async {
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
      debugPrint('[HttpClient] Sending request to ${uri.host}:${uri.port}');

      final request = await _httpClient.getUrl(uri);
      final response = await request.close();

      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        headers[name] = values.join(',');
      });

      final responseBody = await response.transform(utf8.decoder).join();

      setState(() {
        _isLoading = false;

        // 构建响应信息字符串
        final StringBuffer responseInfo = StringBuffer();

        responseInfo.writeln('=== REQUEST (HttpClient) ===');
        responseInfo.writeln('uri: ${uri.toString()}');
        responseInfo.writeln();

        responseInfo.writeln('=== STATUS ===');
        responseInfo.writeln('statusCode: ${response.statusCode}');
        responseInfo.writeln();

        responseInfo.writeln('=== HEADERS ===');
        headers.forEach((key, value) {
          responseInfo.writeln('$key: $value');
        });
        responseInfo.writeln();

        responseInfo.writeln('=== BODY ===');
        if (response.statusCode >= 200 && response.statusCode < 300) {
          try {
            final jsonData = json.decode(responseBody);
            const encoder = JsonEncoder.withIndent('  ');
            responseInfo.write(encoder.convert(jsonData));
          } catch (_) {
            responseInfo.write(responseBody);
          }
        } else {
          responseInfo.write(responseBody);
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
      final res = await HttpdnsPlugin.resolveHostSyncNonBlocking(uri.host, ipType: 'both');
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
