import 'package:flutter/material.dart';
import 'dart:convert';
import 'net/http11.dart';
import 'net/http2.dart';
import 'net/http_result.dart';
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

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _urlController = TextEditingController();
  String _responseText = 'Response will appear here...';
  bool _isLoading = false;

  // 可切换客户端
  late final Http11Client _http11;
  late final Http2Client _http2;
  bool _useHttp2 = false;

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
    _urlController.text = 'https://alidt.alicdn.com/alilog/configs/sdk/common.json';

    _http11 = Http11Client();
    _http2 = Http2Client();
    // 仅首次进入页面时初始化 HTTPDNS
    _initHttpDnsOnce();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  // HTTP请求函数
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
      debugPrint('[connection] Sending request to ${uri.host}:${uri.port} using ${_useHttp2 ? 'HTTP/2' : 'HTTP/1.1'} client');
      final HttpResponseInfo res = _useHttp2
          ? await _http2.get(uri)
          : await _http11.get(uri);

      setState(() {
        _isLoading = false;

        // 构建响应信息字符串
        final StringBuffer responseInfo = StringBuffer();

        // 连接信息
        responseInfo.writeln('=== CONNECTION ===');
        responseInfo.writeln('scheme: ${uri.scheme.toUpperCase()}');
        responseInfo.writeln('target: ${uri.host}:${uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80)}');
        if (res.remoteIp != null && res.remotePort != null) {
          responseInfo.writeln('remote: ${res.remoteIp}:${res.remotePort}');
        }
        if (res.usedProxy && res.proxyHost != null && res.proxyPort != null) {
          responseInfo.writeln('proxy: ${res.proxyHost}:${res.proxyPort}');
        }
        if (res.alpnProtocol != null && res.alpnProtocol!.isNotEmpty) {
          responseInfo.writeln('ALPN: ${res.alpnProtocol}');
        }
        responseInfo.writeln();

        // 添加状态行
        responseInfo.writeln('=== RESPONSE STATUS ===');
        // 尝试从响应头检测HTTP版本，否则不显示版本信息
        String protocolVersion = '';
        final headersMap = res.normalizedHeaders;
        if (headersMap.containsKey('version')) {
          protocolVersion = 'HTTP/${headersMap['version']} ';
        } else if (headersMap.containsKey(':version')) {
          protocolVersion = 'HTTP/${headersMap[':version']} ';
        }
        final int code = res.statusCode;
        final String msg = (res.statusMessage != null && res.statusMessage!.trim().isNotEmpty)
            ? res.statusMessage!.trim()
            : '';
        if (msg.isNotEmpty) {
          responseInfo.writeln('$protocolVersion$code $msg');
        } else {
          responseInfo.writeln('$protocolVersion$code');
        }
        responseInfo.writeln();

        // 添加响应头
        responseInfo.writeln('=== RESPONSE HEADERS ===');
        headersMap.forEach((key, value) {
          responseInfo.writeln('$key: $value');
        });
        responseInfo.writeln();

        // 添加响应体
        responseInfo.writeln('=== RESPONSE BODY ===');
        if (res.statusCode >= 200 && res.statusCode < 300) {
          // 尝试格式化JSON响应以便更好地显示
          try {
            final jsonData = json.decode(res.body);
            const encoder = JsonEncoder.withIndent('  ');
            responseInfo.write(encoder.convert(jsonData));
          } catch (e) {
            // 如果不是JSON，直接显示原始响应
            responseInfo.write(res.body);
          }
        } else {
          responseInfo.write(res.body);
        }

        _responseText = responseInfo.toString();
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _responseText = 'Network Error: $e';
      });
    }
    finally {
      // 关闭自定义客户端，避免连接泄漏
      // 不关闭全局客户端，以便保持连接并复用
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
                hintText: 'https://api.example.com/data',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),

            // 发送按钮
            ElevatedButton.icon(
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

            // 切换 HTTP/1.1 与 HTTP/2 客户端
            Row(
              children: [
                Switch(
                  value: _useHttp2,
                  onChanged: (v) => setState(() => _useHttp2 = v),
                ),
                const SizedBox(width: 8),
                Text(_useHttp2 ? 'HTTP/2 client' : 'HTTP/1.1 client'),
              ],
            ),
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
