# Aliyun HTTPDNS Flutter Plugin

阿里云EMAS HTTPDNS Flutter插件，提供基于原生SDK的域名解析能力。

一、快速入门 
-----------------------

### 1.1 开通服务 

请参考[快速入门文档](https://help.aliyun.com/document_detail/2867674.html)开通HTTPDNS。

### 1.2 获取配置 

请参考开发配置文档在EMAS控制台开发配置中获取AccountId/SecretKey/AESSecretKey等信息，用于初始化SDK。

## 二、安装

在`pubspec.yaml`中加入dependencies：
```yaml
dependencies:
  aliyun_httpdns: ^1.0.1
```
添加依赖之后需要执行一次 `flutter pub get`。

### 原生SDK版本说明

插件已集成了对应平台的HTTPDNS原生SDK，当前版本：

- **Android**: `com.aliyun.ams:alicloud-android-httpdns:2.6.7`
- **iOS**: `AlicloudHTTPDNS:3.3.0`



三、配置和使用 
------------------------

### 3.1 初始化配置 

应用启动后，需要先初始化插件，才能调用HTTPDNS能力。
初始化主要是配置AccountId/SecretKey等信息及功能开关。
示例代码如下：

```dart
// 初始化 HTTPDNS
await AliyunHttpdns.init(
  accountId: '您的AccountId',
  secretKey: '您的SecretKey',
);

// 设置功能选项
await AliyunHttpdns.setHttpsRequestEnabled(true);
await AliyunHttpdns.setLogEnabled(true);
await AliyunHttpdns.setPersistentCacheIPEnabled(true);
await AliyunHttpdns.setReuseExpiredIPEnabled(true);

// 构建服务
await AliyunHttpdns.build();

// 设置预解析域名
await AliyunHttpdns.setPreResolveHosts(['www.aliyun.com'], ipType: 'both');
print("init success");
```



#### 3.1.1 日志配置 

应用开发过程中，如果要输出HTTPDNS的日志，可以调用日志输出控制方法，开启日志，示例代码如下：

```dart
await AliyunHttpdns.setLogEnabled(true);
print("enableLog success");
```



#### 3.1.2 sessionId记录 

应用在运行过程中，可以调用获取SessionId方法获取sessionId，记录到应用的数据采集系统中。
sessionId用于表示标识一次应用运行，线上排查时，可以用于查询应用一次运行过程中的解析日志，示例代码如下：

```dart
final sessionId = await AliyunHttpdns.getSessionId();
print("SessionId = $sessionId");
```



### 3.2 域名解析 

#### 3.2.1 预解析 

当需要提前解析域名时，可以调用预解析域名方法，示例代码如下：

```dart
await AliyunHttpdns.setPreResolveHosts(["www.aliyun.com", "www.example.com"], ipType: 'both');
print("preResolveHosts success");
```



调用之后，插件会发起域名解析，并把结果缓存到内存，用于后续请求时直接使用。

### 3.2.2 域名解析 

当需要解析域名时，可以通过调用域名解析方法解析域名获取IP，示例代码如下：

```dart
Future<void> _resolve() async {
  final res = await AliyunHttpdns.resolveHostSyncNonBlocking('www.aliyun.com', ipType: 'both');
  final ipv4List = res['ipv4'] ?? [];
  final ipv6List = res['ipv6'] ?? [];
  print('IPv4: $ipv4List');
  print('IPv6: $ipv6List');
}
```



四、Flutter最佳实践 
------------------------------

### 4.1 原理说明 

本示例展示了一种更直接的集成方式，通过自定义HTTP客户端适配器来实现HTTPDNS集成：

1. 创建自定义的HTTP客户端适配器，拦截网络请求
2. 在适配器中调用HTTPDNS插件解析域名为IP地址
3. 使用解析得到的IP地址创建直接的Socket连接
4. 对于HTTPS连接，确保正确设置SNI（Server Name Indication）为原始域名

这种方式避免了创建本地代理服务的复杂性，直接在HTTP客户端层面集成HTTPDNS功能。

### 4.2 示例说明 

完整应用示例请参考插件包中example应用。

#### 4.2.1 自定义HTTP客户端适配器实现 

自定义适配器的实现请参考插件包中example/lib/net/httpdns_http_client_adapter.dart文件。本方案由EMAS团队设计实现，参考请注明出处。
适配器内部会拦截HTTP请求，调用HTTPDNS进行域名解析，并使用解析后的IP创建socket连接。

本示例支持三种网络库：Dio、HttpClient、http包。代码如下：

```dart
import 'dart:io';
import 'package:dio/io.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter/foundation.dart';
import 'package:aliyun_httpdns/aliyun_httpdns.dart';

// Dio 适配器
IOHttpClientAdapter buildHttpdnsHttpClientAdapter() {
  final HttpClient client = HttpClient();
  _configureHttpClient(client);
  _configureConnectionFactory(client);

  final IOHttpClientAdapter adapter = IOHttpClientAdapter(createHttpClient: () => client)
    ..validateCertificate = (cert, host, port) => true;
  return adapter;
}

// 原生 HttpClient
HttpClient buildHttpdnsNativeHttpClient() {
  final HttpClient client = HttpClient();
  _configureHttpClient(client);
  _configureConnectionFactory(client);
  return client;
}

// http 包适配器
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
// 本方案由EMAS团队设计实现，参考请注明出处。
void _configureConnectionFactory(HttpClient client) {
  client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
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
    final Future<ConnectionTask<Socket>> rawStart = Socket.startConnect(target, port);
    final Future<Socket> upgraded = rawStart.then((task) async {
      final Socket raw = await task.socket;
      if (cancelled) {
        raw.destroy();
        throw const SocketException('Connection cancelled');
      }
      final SecureSocket secure = await SecureSocket.secure(
        raw,
        host: domain, // 重要：使用原始域名作为SNI
      );
      if (cancelled) {
        secure.destroy();
        throw const SocketException('Connection cancelled');
      }
      return secure;
    });
    return ConnectionTask.fromSocket(
      upgraded,
      () {
        cancelled = true;
        try {
          rawStart.then((t) => t.cancel());
        } catch (_) {}
      },
    );
  };
}

// 通过 HTTPDNS 解析目标 IP 列表
Future<List<InternetAddress>> _resolveTargets(String domain) async {
  try {
    final res = await AliyunHttpdns.resolveHostSyncNonBlocking(domain, ipType: 'both');
    final List<String> ipv4 = res['ipv4'] ?? [];
    final List<String> ipv6 = res['ipv6'] ?? [];
    final List<InternetAddress> targets = [
      ...ipv4.map(InternetAddress.tryParse).whereType<InternetAddress>(),
      ...ipv6.map(InternetAddress.tryParse).whereType<InternetAddress>(),
    ];
    if (targets.isEmpty) {
      debugPrint('[dio] HTTPDNS no result for $domain, fallback to system DNS');
    } else {
      debugPrint('[dio] HTTPDNS resolved $domain -> ${targets.first.address}');
    }
    return targets;
  } catch (e) {
    debugPrint('[dio] HTTPDNS resolve failed: $e, fallback to system DNS');
    return const <InternetAddress>[];
  }
}
```



#### 4.2.2 适配器集成和使用 

适配器的集成请参考插件包中example/lib/main.dart文件。
首先需要初始化HTTPDNS，然后配置网络库使用自定义适配器，示例代码如下：

```dart
class _MyHomePageState extends State<MyHomePage> {
  late final Dio _dio;
  late final HttpClient _httpClient;
  late final http.Client _httpPackageClient;

  @override
  void initState() {
    super.initState();
    
    // 初始化 HTTPDNS
    _initHttpDnsOnce();
    
    // 配置网络库使用 HTTPDNS 适配器
    _dio = Dio();
    _dio.httpClientAdapter = buildHttpdnsHttpClientAdapter();
    _dio.options.headers['Connection'] = 'keep-alive';
    
    _httpClient = buildHttpdnsNativeHttpClient();
    _httpPackageClient = buildHttpdnsHttpPackageClient();
  }

  Future<void> _initHttpDnsOnce() async {
    try {
      await AliyunHttpdns.init(
        accountId: 000000,
        secretKey: '您的SecretKey',
      );
      await AliyunHttpdns.setHttpsRequestEnabled(true);
      await AliyunHttpdns.setLogEnabled(true);
      await AliyunHttpdns.setPersistentCacheIPEnabled(true);
      await AliyunHttpdns.setReuseExpiredIPEnabled(true);
      await AliyunHttpdns.build();
      
      // 设置预解析域名
      await AliyunHttpdns.setPreResolveHosts(['www.aliyun.com'], ipType: 'both');
    } catch (e) {
      debugPrint('[httpdns] init failed: $e');
    }
  }
}
```



使用配置好的网络库发起请求时，会自动使用HTTPDNS进行域名解析：

```dart
// 使用 Dio
final response = await _dio.get('https://www.aliyun.com');

// 使用 HttpClient
final request = await _httpClient.getUrl(Uri.parse('https://www.aliyun.com'));
final response = await request.close();

// 使用 http 包
final response = await _httpPackageClient.get(Uri.parse('https://www.aliyun.com'));
```

#### 4.2.3 资源清理 

在组件销毁时，记得清理相关资源：

```dart
@override
void dispose() {
  _urlController.dispose();
  _httpClient.close();
  _httpPackageClient.close();
  super.dispose();
}
```



五、API 
----------------------

### 5.1 日志输出控制 

控制是否打印Log。

```dart
await AliyunHttpdns.setLogEnabled(true);
print("enableLog success");
```



### 5.2 初始化 

初始化配置, 在应用启动时调用。

```dart
// 基础初始化
await AliyunHttpdns.init(
  accountId: 000000,
  secretKey: 'your_secret_key',
  aesSecretKey: 'your_aes_secret_key', // 可选
);

// 配置功能选项
await AliyunHttpdns.setHttpsRequestEnabled(true);
await AliyunHttpdns.setLogEnabled(true);
await AliyunHttpdns.setPersistentCacheIPEnabled(true);
await AliyunHttpdns.setReuseExpiredIPEnabled(true);

// 构建服务实例
await AliyunHttpdns.build();

print("init success");
```



初始化参数:

| 参数名          | 类型     | 是否必须 | 功能         | 支持平台        |
|-------------|--------|------|------------|-------------|
| accountId   | int    | 必选参数 | Account ID | Android/iOS |
| secretKey   | String | 可选参数 | 加签密钥       | Android/iOS |
| aesSecretKey| String | 可选参数 | 加密密钥       | Android/iOS |

功能配置方法:

- `setHttpsRequestEnabled(bool)` - 设置是否使用HTTPS解析链路
- `setLogEnabled(bool)` - 设置是否开启日志
- `setPersistentCacheIPEnabled(bool)` - 设置是否开启持久化缓存
- `setReuseExpiredIPEnabled(bool)` - 设置是否允许复用过期IP
- `setPreResolveAfterNetworkChanged(bool)` - 设置网络切换时是否自动刷新解析



### 5.3 域名解析 

解析指定域名。

```dart
Future<void> _resolve() async {
  final res = await AliyunHttpdns.resolveHostSyncNonBlocking(
    'www.aliyun.com', 
    ipType: 'both',  // 'auto', 'ipv4', 'ipv6', 'both'
  );
  
  final ipv4List = res['ipv4'] ?? [];
  final ipv6List = res['ipv6'] ?? [];
  print('IPv4: $ipv4List');
  print('IPv6: $ipv6List');
}
```



参数:

| 参数名        | 类型                  | 是否必须 | 功能                                      |
|------------|---------------------|------|----------------------------------------|
| hostname   | String              | 必选参数 | 要解析的域名                                 |
| ipType     | String              | 可选参数 | 请求IP类型: 'auto', 'ipv4', 'ipv6', 'both' |



返回数据结构:

| 字段名  | 类型           | 功能                               |
|------|--------------|----------------------------------|
| ipv4 | List<String> | IPv4地址列表，如: ["1.1.1.1", "2.2.2.2"] |
| ipv6 | List<String> | IPv6地址列表，如: ["::1", "::2"]         |



### 5.4 预解析域名 

预解析域名, 解析后缓存在SDK中,下次解析时直接从缓存中获取,提高解析速度。

```dart
await AliyunHttpdns.setPreResolveHosts(
  ["www.aliyun.com", "www.example.com"], 
  ipType: 'both'
);
print("preResolveHosts success");
```



参数:

| 参数名    | 类型           | 是否必须 | 功能                                      |
|--------|--------------|------|----------------------------------------|
| hosts  | List<String> | 必选参数 | 预解析域名列表                                |
| ipType | String       | 可选参数 | 请求IP类型: 'auto', 'ipv4', 'ipv6', 'both' |



### 5.5 获取SessionId 

获取SessionId, 用于排查追踪问题。

```dart
final sessionId = await AliyunHttpdns.getSessionId();
print("SessionId = $sessionId");
```



无需参数，直接返回当前会话ID。

### 5.6 清除缓存 

清除所有DNS解析缓存。

```dart
await AliyunHttpdns.cleanAllHostCache();
print("缓存清除成功");
```

### 5.7 持久化缓存配置 

设置是否开启持久化缓存功能。开启后，SDK 会将解析结果保存到本地，App 重启后可以从本地加载缓存，提升首屏加载速度。

```dart
// 基础用法：开启持久化缓存
await AliyunHttpdns.setPersistentCacheIPEnabled(true);

// 高级用法：开启持久化缓存并设置过期时间阈值
await AliyunHttpdns.setPersistentCacheIPEnabled(
  true, 
  discardExpiredAfterSeconds: 86400  // 1天，单位：秒
);
print("持久化缓存已开启");
```

参数:

| 参数名                        | 类型   | 是否必须 | 功能                                      |
|----------------------------|------|------|------------------------------------------|
| enabled                    | bool | 必选参数 | 是否开启持久化缓存                              |
| discardExpiredAfterSeconds | int  | 可选参数 | 过期时间阈值（秒），App 启动时会丢弃过期超过此时长的缓存记录，建议设置为 1 天（86400 秒） |

注意事项:
- 持久化缓存仅影响第一次域名解析结果，后续解析仍会请求 HTTPDNS 服务器
- 如果业务服务器 IP 变化频繁，建议谨慎开启此功能
- 建议在 `build()` 之前调用此接口

### 5.8 网络变化时自动刷新预解析 

设置在网络环境变化时是否自动刷新预解析域名的缓存。

```dart
await AliyunHttpdns.setPreResolveAfterNetworkChanged(true);
print("网络变化自动刷新已启用");
```

### 5.9 IP 优选 

设置需要进行 IP 优选的域名列表。开启后，SDK 会对解析返回的 IP 列表进行 TCP 测速并排序，优先返回连接速度最快的 IP。

```dart
await AliyunHttpdns.setIPRankingList({
  'www.aliyun.com': 443,
});
print("IP 优选配置成功");
```

参数:

| 参数名         | 类型              | 是否必须 | 功能                          |
|-------------|-----------------|------|------------------------------|
| hostPortMap | Map<String, int> | 必选参数 | 域名和端口的映射，例如：{'www.aliyun.com': 443} |



