package com.follow.clash.plugins

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

internal class MainThreadResult(
    private val delegate: MethodChannel.Result,
) : MethodChannel.Result {
    override fun success(result: Any?) = post { delegate.success(result) }

    override fun error(code: String, message: String?, details: Any?) =
        post { delegate.error(code, message, details) }

    override fun notImplemented() = post { delegate.notImplemented() }

    private fun post(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post(block)
        }
    }

    private companion object {
        val mainHandler = Handler(Looper.getMainLooper())
    }
}
