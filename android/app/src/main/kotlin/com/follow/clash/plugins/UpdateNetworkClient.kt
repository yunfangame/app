package com.follow.clash.plugins

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import com.follow.clash.common.GlobalState
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.Proxy
import java.net.SocketTimeoutException
import java.net.URI
import java.net.UnknownHostException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.ssl.SSLException

internal object UpdateRequestPolicy {
    const val MAX_BYTES = 1024 * 1024

    fun valid(url: String, kind: String): Boolean = runCatching {
        val uri = URI(url)
        uri.scheme == "https" && !uri.host.isNullOrEmpty() &&
            uri.rawUserInfo == null && uri.rawFragment == null &&
            uri.port in listOf(-1, 443) && when (kind) {
                "main_config" -> uri.host in listOf(
                    "house.zryc.tech", "zryc.oss-cn-beijing.aliyuncs.com",
                ) && uri.path == "/ConFigOss4.json"
                "update_manifest" -> true
                else -> false
            }
    }.getOrDefault(false)

    fun read(input: java.io.InputStream): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            require(output.size() + count <= MAX_BYTES) { "UPDATE_SIZE" }
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }
}

internal class UpdateNetworkClient(context: Context, private val scope: CoroutineScope) {
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private val pending = ConcurrentHashMap<String, Request>()
    private val permits = Semaphore(4)
    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    private var closed = false

    private inner class Request(val id: String, val result: Result) {
        val finished = AtomicBoolean(false)
        val started = System.nanoTime()
        @Volatile var connection: HttpURLConnection? = null

        fun finish(code: String? = null, details: Any? = null, bytes: ByteArray? = null) {
            if (!finished.compareAndSet(false, true)) return
            pending.remove(id, this)
            GlobalState.log(
                "app.update.underlay.completed id=$id result=${code ?: "ok"} " +
                    "elapsed_ms=${(System.nanoTime() - started) / 1_000_000}",
            )
            if (code == null) result.success(bytes)
            else result.error(code, "Update configuration request failed", details)
        }

        fun cancel(code: String) {
            finish(code)
            connection?.disconnect()
        }
    }

    fun fetch(id: String, url: String, kind: String, result: Result) {
        if (closed || !id.matches(Regex("update-[0-9]+-[0-9]+")) ||
            !UpdateRequestPolicy.valid(url, kind)
        ) {
            result.error("UPDATE_INVALID", "Invalid update request", null)
            return
        }
        if (!permits.tryAcquire()) {
            result.error("UPDATE_BUSY", "Update transport busy", null)
            return
        }
        val request = Request(id, result)
        if (pending.putIfAbsent(id, request) != null) {
            permits.release()
            result.error("UPDATE_INVALID", "Duplicate update request", null)
            return
        }
        val deadline = scheduler.schedule(
            { request.cancel("UPDATE_TIMEOUT") }, 7, TimeUnit.SECONDS,
        )
        scope.launch(Dispatchers.IO) {
            try {
                val network = underlyingNetwork()
                if (network == null) {
                    request.finish("UPDATE_NETWORK")
                    return@launch
                }
                if (request.finished.get()) return@launch
                val activeIsVpn = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
                    ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
                GlobalState.log(
                    "app.update.underlay.selected id=$id kind=$kind " +
                        "vpn_active=$activeIsVpn network=$network proxy=none",
                )
                val connection = network.openConnection(URI(url).toURL(), Proxy.NO_PROXY)
                    as HttpURLConnection
                request.connection = connection
                if (request.finished.get()) return@launch
                connection.apply {
                    connectTimeout = 4000
                    readTimeout = 4000
                    instanceFollowRedirects = false
                    useCaches = false
                    setRequestProperty("Accept", "application/json")
                    setRequestProperty("Cache-Control", "no-cache, no-store, max-age=0")
                    setRequestProperty("Pragma", "no-cache")
                }
                val status = connection.responseCode
                GlobalState.log("app.update.underlay.response id=$id kind=$kind status=$status")
                if (status !in 200..299) {
                    request.finish("UPDATE_HTTP", status)
                } else if (connection.contentLengthLong > UpdateRequestPolicy.MAX_BYTES) {
                    request.finish("UPDATE_SIZE")
                } else {
                    val bytes = connection.inputStream.use(UpdateRequestPolicy::read)
                    request.finish(bytes = bytes)
                }
            } catch (_: SocketTimeoutException) {
                request.finish("UPDATE_TIMEOUT")
            } catch (_: UnknownHostException) {
                request.finish("UPDATE_DNS")
            } catch (_: SSLException) {
                request.finish("UPDATE_TLS")
            } catch (_: IllegalArgumentException) {
                request.finish("UPDATE_SIZE")
            } catch (_: Exception) {
                request.finish("UPDATE_NETWORK")
            } finally {
                request.connection?.disconnect()
                deadline.cancel(false)
                permits.release()
            }
        }
    }

    private fun underlyingNetwork(): Network? = connectivity.allNetworks
        .filter { network ->
            connectivity.getNetworkCapabilities(network)?.let {
                it.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                    it.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            } == true
        }
        .maxByOrNull { network ->
            val capabilities = connectivity.getNetworkCapabilities(network)
            (if (network == connectivity.activeNetwork) 2 else 0) +
                (if (capabilities?.hasCapability(
                        NetworkCapabilities.NET_CAPABILITY_VALIDATED,
                    ) == true
                ) 1 else 0)
        }

    fun cancel(id: String) {
        pending[id]?.cancel("UPDATE_CANCELLED")
    }

    fun close() {
        closed = true
        pending.values.toList().forEach { it.cancel("UPDATE_CANCELLED") }
        scheduler.shutdownNow()
    }
}
