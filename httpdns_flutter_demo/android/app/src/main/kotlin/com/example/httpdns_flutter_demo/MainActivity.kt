package com.example.httpdns_flutter_demo

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.ProxySelector
import java.net.URI

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "system_proxy")
        channel.setMethodCallHandler { call, result ->
            if (call.method == "getProxyForUrl") {
                val urlString = call.argument<String>("url")
                if (urlString.isNullOrBlank()) {
                    Log.w("SystemProxy", "url argument is null or blank")
                    result.success(null)
                    return@setMethodCallHandler
                }

                try {
                    val uri = URI(urlString)
                    val selector = ProxySelector.getDefault()
                    val proxies = selector?.select(uri)

                    if (proxies.isNullOrEmpty()) {
                        Log.d("SystemProxy", "No proxy configured for URL: $urlString")
                        result.success(null)
                        return@setMethodCallHandler
                    }

                    val proxy = proxies.first()
                    when (proxy.type()) {
                        Proxy.Type.DIRECT -> {
                            Log.d("SystemProxy", "Using DIRECT connection for URL: $urlString")
                            result.success("DIRECT")
                        }

                        Proxy.Type.HTTP, Proxy.Type.SOCKS -> {
                            val address = proxy.address()
                            if (address is InetSocketAddress) {
                                val host = address.hostString
                                val port = address.port
                                val typeString = if (proxy.type() == Proxy.Type.SOCKS) "SOCKS" else "PROXY"
                                val value = "$typeString $host:$port"
                                Log.d("SystemProxy", "Resolved proxy for URL: $urlString -> $value")
                                result.success(value)
                            } else {
                                Log.w("SystemProxy", "Proxy address is not InetSocketAddress for URL: $urlString")
                                result.success(null)
                            }
                        }

                        else -> {
                            Log.w("SystemProxy", "Unknown proxy type for URL: $urlString -> ${proxy.type()}")
                            result.success(null)
                        }
                    }
                } catch (e: Exception) {
                    Log.e("SystemProxy", "Failed to resolve proxy for URL: $urlString", e)
                    result.success(null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
