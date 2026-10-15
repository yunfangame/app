package com.follow.clash.plugins

import java.io.ByteArrayInputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateRequestPolicyTest {
    @Test
    fun mainConfigOnlyAllowsKnownHttpsSources() {
        assertTrue(UpdateRequestPolicy.valid("https://house.zryc.tech/ConFigOss4.json", "main_config"))
        assertTrue(UpdateRequestPolicy.valid("https://zryc.oss-cn-beijing.aliyuncs.com/ConFigOss4.json", "main_config"))
        for (url in listOf(
            "http://house.zryc.tech/ConFigOss4.json",
            "https://house.zryc.tech.evil.example/ConFigOss4.json",
            "https://user:password@house.zryc.tech/ConFigOss4.json",
            "https://house.zryc.tech:444/ConFigOss4.json",
            "https://house.zryc.tech/other.json",
            "https://house.zryc.tech/ConFigOss4.json#fragment",
        )) assertFalse(UpdateRequestPolicy.valid(url, "main_config"))
    }

    @Test
    fun permitsConfiguredHttpsManifestsButNotOtherMethods() {
        assertTrue(UpdateRequestPolicy.valid("https://updates.example/custom.json", "update_manifest"))
        assertFalse(UpdateRequestPolicy.valid("http://updates.example/custom.json", "update_manifest"))
        assertFalse(UpdateRequestPolicy.valid("https://updates.example/custom.json", "download"))
    }

    @Test
    fun limitsStreamingResponsesWithoutContentLength() {
        assertEquals(12, UpdateRequestPolicy.read(ByteArrayInputStream(ByteArray(12))).size)
        assertEquals(UpdateRequestPolicy.MAX_BYTES, UpdateRequestPolicy.read(
            ByteArrayInputStream(ByteArray(UpdateRequestPolicy.MAX_BYTES)),
        ).size)
        try {
            UpdateRequestPolicy.read(ByteArrayInputStream(ByteArray(UpdateRequestPolicy.MAX_BYTES + 1)))
            throw AssertionError("Oversized response accepted")
        } catch (expected: IllegalArgumentException) {
            assertEquals("UPDATE_SIZE", expected.message)
        }
    }
}
