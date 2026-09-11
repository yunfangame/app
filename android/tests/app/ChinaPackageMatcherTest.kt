package com.follow.clash.packages

import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test

class ChinaPackageMatcherTest {
    private val matcherClass = runCatching {
        Class.forName("com.follow.clash.packages.ChinaPackageMatcher")
    }.getOrNull()
    private val matcherInstance = matcherClass?.getDeclaredField("INSTANCE")?.get(null)

    @Before
    fun requireProductionMatcher() {
        assumeTrue("ChinaPackageMatcher is not part of this customized branch", matcherClass != null)
    }

    private fun invokeBoolean(method: String, value: String): Boolean =
        matcherClass!!.getDeclaredMethod(method, String::class.java).apply {
            isAccessible = true
        }.invoke(matcherInstance, value) as Boolean

    private fun invokeString(method: String, value: String): String =
        matcherClass!!.getDeclaredMethod(method, String::class.java).apply {
            isAccessible = true
        }.invoke(matcherInstance, value) as String

    private fun matchesKnownPrefix(value: String): Boolean =
        invokeBoolean("matchesKnownPrefix", value)

    private fun isSkipped(value: String): Boolean = invokeBoolean("isSkipped", value)

    private fun classNameOf(value: String): String = invokeString("classNameOf", value)

    @Test
    fun `known vendors and SDKs match`() {
        val names = listOf(
            "com.tencent.mm",
            "com.alipay.android.app",
            "com.taobao.taobao",
            "com.baidu.searchbox",
            "com.bytedance.sdk.openadsdk",
            "com.netease.cloudmusic",
            "com.unionpay.tsmservice",
            "cn.wps.moffice",
            "andes.oplus.internal",
        )
        for (name in names) {
            assertTrue(name, matchesKnownPrefix(name))
        }
    }

    @Test
    fun `packer signatures used as class names match`() {
        val classNames = listOf(
            "com.secneo.apkwrapper.H",
            "s.h.e.l.l.S",
            "com.stub.StubApp",
            "com.kiwisec.KiwiSecApplication",
            "com.secshell.shellwrapper.SecAppWrapper",
            "com.wrapper.proxyapplication.WrapperProxyApplication",
            "cn.securitystack.stack.StackApplication",
        )
        for (name in classNames) {
            assertTrue(name, matchesKnownPrefix(name))
        }
    }

    /**
     * The prefixes carry no dot boundary on purpose. Adding one would look
     * tidier and would silently stop detecting 360 and the Alibaba clouds,
     * whose packages extend the prefix without a separator.
     */
    @Test
    fun `prefixes deliberately match without a separator`() {
        assertTrue(matchesKnownPrefix("com.qihoo360.mobilesafe"))
        assertTrue(matchesKnownPrefix("com.aliyun.linkcard"))
        assertTrue(matchesKnownPrefix("com.alimama.moon"))
    }

    @Test
    fun `a bare prefix matches on its own`() {
        assertTrue(matchesKnownPrefix("com.tencent"))
    }

    @Test
    fun `unrelated packages do not match`() {
        val names = listOf(
            "org.mozilla.firefox",
            "com.spotify.music",
            "de.telekom.mail",
            "com.whatsapp",
        )
        for (name in names) {
            assertFalse(name, matchesKnownPrefix(name))
        }
    }

    /**
     * These two do match a prefix, which is exactly why they have to be skipped
     * explicitly: MX Player is caught by `com.mx` (meant for Maxthon) and
     * StubHub by `com.stub` (meant for the StubApp packer).
     */
    @Test
    fun `loose prefixes drag in unrelated apps that the skip list removes`() {
        assertTrue(matchesKnownPrefix("com.mxtech.videoplayer.ad"))
        assertTrue(isSkipped("com.mxtech.videoplayer.ad"))

        assertTrue(matchesKnownPrefix("com.stubhub"))
        assertTrue(isSkipped("com.stubhub"))
    }

    @Test
    fun `the intended owners of those prefixes still match and are not skipped`() {
        assertTrue(matchesKnownPrefix("com.mx.browser"))
        assertFalse(isSkipped("com.mx.browser"))

        assertTrue(matchesKnownPrefix("com.stub.StubApp"))
        assertFalse(isSkipped("com.stub.StubApp"))
    }

    @Test
    fun `the skip list applies a dot boundary`() {
        assertTrue(isSkipped("com.google"))
        assertTrue(isSkipped("com.google.android.gms"))
        assertFalse(
            "com.googlefoo is a different vendor",
            isSkipped("com.googlefoo"),
        )
    }

    @Test
    fun `skipping wins over a matching prefix`() {
        // TikTok ships domestic SDKs but must stay out of the domestic list.
        assertTrue(isSkipped("com.zhiliaoapp.musically"))
    }

    @Test
    fun `dex descriptors are normalized before matching`() {
        assertEquals(
            "com.tencent.mm.Foo.Bar",
            classNameOf("Lcom/tencent/mm/Foo\$Bar;"),
        )
        assertTrue(
            matchesKnownPrefix(
                classNameOf("Lcom/qihoo360/replugin/Entry;"),
            ),
        )
    }

    @Test
    fun `an already normalized name survives normalization`() {
        assertEquals("com.example.Foo", classNameOf("com.example.Foo"))
    }
}
