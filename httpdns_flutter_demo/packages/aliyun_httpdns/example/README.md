# aliyun_httpdns_example

Demonstrates how to use the aliyun_httpdns plugin with various network libraries.

## Features

This example demonstrates:
- HTTPDNS initialization and configuration
- Domain name resolution (IPv4 and IPv6)
- Integration with multiple network libraries:
  - Dio
  - HttpClient
  - http package
- Custom HTTP client adapter for HTTPDNS
- Real HTTP requests using HTTPDNS resolution

## Getting Started

1. Replace the `accountId` and `secretKey` in `lib/main.dart` with your own credentials:
   ```dart
   await AliyunHttpdns.init(
     accountId: YOUR_ACCOUNT_ID,  // Replace with your account ID
     secretKey: 'YOUR_SECRET_KEY', // Replace with your secret key
   );
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   flutter run
   ```

4. Try the features:
   - Enter a URL and select a network library (Dio/HttpClient/http)
   - Tap "Send Request" to make an HTTP request using HTTPDNS
   - Tap "HTTPDNS Resolve" to test domain resolution directly

## Implementation Details

The example uses a modern approach with `HttpClient.connectionFactory` to integrate HTTPDNS:
- See `lib/net/httpdns_http_client_adapter.dart` for the implementation
- This approach avoids the complexity of local proxy servers
- Works seamlessly with Dio, HttpClient, and http package

## Note

The credentials in this example are placeholders. Please obtain your own credentials from the [Aliyun HTTPDNS Console](https://help.aliyun.com/document_detail/2867674.html).
