package com.aliyun.ams.httpdns

import android.content.Context
import android.util.Log
import androidx.annotation.NonNull

import com.alibaba.sdk.android.httpdns.HttpDns
import com.alibaba.sdk.android.httpdns.HttpDnsService
import com.alibaba.sdk.android.httpdns.InitConfig
import com.alibaba.sdk.android.httpdns.RequestIpType
import com.alibaba.sdk.android.httpdns.log.HttpDnsLog
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result


class AliyunHttpDnsPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var appContext: Context? = null

    // Cached service keyed by accountId to avoid re-creating
    private var service: HttpDnsService? = null
    private var accountId: String? = null
    private var secretKey: String? = null
    private var aesSecretKey: String? = null

    // Desired states collected before build()
    private var desiredPersistentCacheEnabled: Boolean? = null
    private var desiredDiscardExpiredAfterSeconds: Int? = null
    private var desiredReuseExpiredIPEnabled: Boolean? = null
    private var desiredLogEnabled: Boolean? = null
    private var desiredHttpsEnabled: Boolean? = null
    private var desiredPreResolveAfterNetworkChanged: Boolean? = null
    private var desiredIPRankingMap: Map<String, Int>? = null





    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        appContext = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "aliyun_httpdns")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        // Log every incoming call with method name and raw arguments
        try {
            Log.i("AliyunHttpDns", "invoke method=${call.method}, args=${call.arguments}")
        } catch (_: Throwable) {
            Log.i("AliyunHttpDns", "invoke method=${call.method}, args=<unprintable>")
        }
        when (call.method) {
            // Dart: init(accountId, secretKey?, aesSecretKey?) — only save states here
            "initialize" -> {
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                val ctx = appContext
                if (ctx == null) {
                    result.error("no_context", "Android context not attached", null)
                    return
                }
                val accountAny = args["accountId"]
                val account = when (accountAny) {
                    is Int -> accountAny.toString()
                    is Long -> accountAny.toString()
                    is String -> accountAny
                    else -> null
                }
                val secret = (args["secretKey"] as? String)?.takeIf { it.isNotBlank() }
                val aes = (args["aesSecretKey"] as? String)?.takeIf { it.isNotBlank() }

                if (account.isNullOrBlank()) {
                    Log.i("AliyunHttpDns", "initialize missing accountId")
                    result.success(false)
                    return
                }
                // Save desired states only; actual build happens on 'build'
                accountId = account
                secretKey = secret
                aesSecretKey = aes
                Log.i("AliyunHttpDns", "initialize saved state, account=$account")
                result.success(true)
            }



            // Dart: setLogEnabled(enabled) — save desired
            "setLogEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") == true
                desiredLogEnabled = enabled
                Log.i("AliyunHttpDns", "setLogEnabled desired=$enabled")
                result.success(null)
            }

            // Dart: setHttpsRequestEnabled(enabled)
            "setHttpsRequestEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") == true
                desiredHttpsEnabled = enabled
                Log.i("AliyunHttpDns", "https request desired=$enabled")
                result.success(null)
            }

            // Dart: setPersistentCacheIPEnabled(enabled, discardExpiredAfterSeconds?) — save desired
            "setPersistentCacheIPEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") == true
                val discard = call.argument<Int>("discardExpiredAfterSeconds")
                desiredPersistentCacheEnabled = enabled
                desiredDiscardExpiredAfterSeconds = discard
                Log.i("AliyunHttpDns", "persistent cache desired=$enabled discard=$discard")
                result.success(null)
            }

            // Dart: setReuseExpiredIPEnabled(enabled) — save desired
            "setReuseExpiredIPEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") == true
                desiredReuseExpiredIPEnabled = enabled
                Log.i("AliyunHttpDns", "reuse expired ip desired=$enabled")
                result.success(null)
            }

            // Dart: setPreResolveAfterNetworkChanged(enabled) — save desired (applied at build via InitConfig)
            "setPreResolveAfterNetworkChanged" -> {
                val enabled = call.argument<Boolean>("enabled") == true
                desiredPreResolveAfterNetworkChanged = enabled
                Log.i("AliyunHttpDns", "preResolveAfterNetworkChanged desired=$enabled")
                result.success(null)
            }

            // Dart: setIPRankingList(hostPortMap) — save desired
            "setIPRankingList" -> {
                val hostPortMap = call.argument<Map<String, Int>>("hostPortMap")
                desiredIPRankingMap = hostPortMap
                Log.i("AliyunHttpDns", "IP ranking list desired, hosts=${hostPortMap?.keys?.joinToString()}")
                result.success(null)
            }

            // Dart: setPreResolveHosts(hosts, ipType)
            "setPreResolveHosts" -> {
                val hosts = call.argument<List<String>>("hosts") ?: emptyList()
                val ipTypeStr = call.argument<String>("ipType") ?: "auto"
                val type = when (ipTypeStr.lowercase()) {
                    "ipv4", "v4" -> RequestIpType.v4
                    "ipv6", "v6" -> RequestIpType.v6
                    "both", "64" -> RequestIpType.both
                    else -> RequestIpType.auto
                }
                try {
                    service?.setPreResolveHosts(hosts, type)
                    Log.i("AliyunHttpDns", "preResolve set for ${hosts.size} hosts, type=$type")
                } catch (t: Throwable) {
                    Log.i("AliyunHttpDns", "setPreResolveHosts failed: ${t.message}")
                }
                result.success(null)
            }

            // Dart: getSessionId
            "getSessionId" -> {
                val sid = try { service?.getSessionId() } catch (_: Throwable) { null }
                result.success(sid)
            }

            // Dart: cleanAllHostCache
            "cleanAllHostCache" -> {
                try {
                    // Best-effort: empty list to clear all
                    service?.cleanHostCache(ArrayList())
                } catch (t: Throwable) {
                    Log.i("AliyunHttpDns", "cleanAllHostCache failed: ${t.message}")
                }
                result.success(null)
            }

            // Dart: build() — construct InitConfig and acquire service using desired states
            "build" -> {
                val ctx = appContext
                val account = accountId
                if (ctx == null || account.isNullOrBlank()) {
                    result.success(false)
                    return
                }
                try {
                    desiredLogEnabled?.let { enabled ->
                        try {
                            HttpDnsLog.enable(enabled)
                            Log.i("AliyunHttpDns", "HttpDnsLog.enable($enabled)")
                        } catch (t: Throwable) {
                            Log.w("AliyunHttpDns", "HttpDnsLog.enable failed: ${t.message}")
                        }
                    }
                    
                    val builder = InitConfig.Builder()

                    // Optional builder params
                    try { builder.javaClass.getMethod("setContext", Context::class.java).invoke(builder, ctx) } catch (_: Throwable) {}
                    try {
                        if (!secretKey.isNullOrBlank()) {
                            builder.javaClass.getMethod("setSecretKey", String::class.java).invoke(builder, secretKey)
                        }
                    } catch (_: Throwable) {}
                    try {
                        if (!aesSecretKey.isNullOrBlank()) {
                            builder.javaClass.getMethod("setAesSecretKey", String::class.java).invoke(builder, aesSecretKey)
                        }
                    } catch (_: Throwable) {}
                    // Prefer HTTPS if requested
                    try {
                        desiredHttpsEnabled?.let { en ->
                            builder.javaClass.getMethod("setEnableHttps", Boolean::class.javaPrimitiveType).invoke(builder, en)
                        }
                    } catch (_: Throwable) {}
                    try {
                        desiredPersistentCacheEnabled?.let { enabled ->
                            val discardSeconds = desiredDiscardExpiredAfterSeconds
                            if (discardSeconds != null && discardSeconds >= 0) {
                                val expiredThresholdMillis = discardSeconds.toLong() * 1000L
                                builder.javaClass.getMethod("setEnableCacheIp", Boolean::class.javaPrimitiveType, Long::class.javaPrimitiveType)
                                    .invoke(builder, enabled, expiredThresholdMillis)
                            } else {
                                builder.javaClass.getMethod("setEnableCacheIp", Boolean::class.javaPrimitiveType)
                                    .invoke(builder, enabled)
                            }
                        }
                    } catch (_: Throwable) { }
                    try {
                        desiredReuseExpiredIPEnabled?.let { enabled ->
                            builder.javaClass.getMethod("setEnableExpiredIp", Boolean::class.javaPrimitiveType)
                                .invoke(builder, enabled)
                        }
                    } catch (_: Throwable) { }
                    // Apply preResolve-after-network-changed
                    try {
                        desiredPreResolveAfterNetworkChanged?.let { en ->
                            builder.javaClass.getMethod("setPreResolveAfterNetworkChanged", Boolean::class.javaPrimitiveType).invoke(builder, en)
                        }
                    } catch (_: Throwable) {}
                    
                    // Apply IP ranking list
                    try {
                        desiredIPRankingMap?.let { map ->
                            if (map.isNotEmpty()) {
                                // Create List<IPRankingBean>
                                val ipRankingBeanClass = Class.forName("com.alibaba.sdk.android.httpdns.ranking.IPRankingBean")
                                val constructor = ipRankingBeanClass.getConstructor(String::class.java, Int::class.javaPrimitiveType)
                                val list = ArrayList<Any>()
                                map.forEach { (host, port) ->
                                    val bean = constructor.newInstance(host, port)
                                    list.add(bean)
                                }
                                val m = builder.javaClass.getMethod("setIPRankingList", List::class.java)
                                m.invoke(builder, list)
                                Log.i("AliyunHttpDns", "setIPRankingList applied with ${list.size} hosts")
                            }
                        }
                    } catch (t: Throwable) {
                        Log.w("AliyunHttpDns", "setIPRankingList failed: ${t.message}")
                    }

                    builder.buildFor(account)

                    service = if (!secretKey.isNullOrBlank()) {
                        HttpDns.getService(ctx, account, secretKey)
                    } else {
                        HttpDns.getService(ctx, account)
                    }
                    
                    Log.i("AliyunHttpDns", "build completed for account=$account")
                    result.success(true)
                } catch (t: Throwable) {
                    Log.i("AliyunHttpDns", "build failed: ${t.message}")
                    result.success(false)
                }
            }

            // Dart: resolveHostSyncNonBlocking(hostname, ipType, sdnsParams?, cacheKey?)
            "resolveHostSyncNonBlocking" -> {
                val hostname = call.argument<String>("hostname")
                if (hostname.isNullOrBlank()) {
                    result.success(mapOf("ipv4" to emptyList<String>(), "ipv6" to emptyList<String>()))
                    return
                }
                val ipTypeStr = call.argument<String>("ipType") ?: "auto"
                val type = when (ipTypeStr.lowercase()) {
                    "ipv4", "v4" -> RequestIpType.v4
                    "ipv6", "v6" -> RequestIpType.v6
                    "both", "64" -> RequestIpType.both
                    else -> RequestIpType.auto
                }
                try {
                    val svc = service ?: run {
                        val ctx = appContext
                        val acc = accountId
                        if (ctx != null && !acc.isNullOrBlank()) HttpDns.getService(ctx, acc) else null
                    }
                    val r = svc?.getHttpDnsResultForHostSyncNonBlocking(hostname, type)
                    val v4 = r?.ips?.toList() ?: emptyList()
                    val v6 = r?.ipv6s?.toList() ?: emptyList()
                    // 记录解析结果，便于排查：包含 host、请求类型以及返回的 IPv4/IPv6 列表
                    Log.d(
                        "HttpdnsPlugin",
                        "resolve result host=" + hostname + ", type=" + type +
                            ", ipv4=" + v4.joinToString(prefix = "[", postfix = "]") +
                            ", ipv6=" + v6.joinToString(prefix = "[", postfix = "]")
                    )
                    result.success(mapOf("ipv4" to v4, "ipv6" to v6))
                } catch (t: Throwable) {
                    Log.i("AliyunHttpDns", "resolveHostSyncNonBlocking failed: ${t.message}")
                    result.success(mapOf("ipv4" to emptyList<String>(), "ipv6" to emptyList<String>()))
                }
            }

            // Legacy methods removed: preResolve / clearCache handled at app layer if needed

            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        service = null
        appContext = null
    }
}
