package com.follow.clash.plugins

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class AppUpdatePackagePolicyTest {
    @get:Rule
    val temporary = TemporaryFolder()

    @Test
    fun acceptsOnlyCompletedApkWithinUpdateCache() {
        val updateDirectory = temporary.newFolder("fengwo-app-updates", "download-123")
        val apk = File(updateDirectory, "FengWo.apk").apply { writeText("apk") }
        assertEquals(apk.canonicalFile, AppUpdatePackagePolicy.resolveApk(temporary.root, apk.path))
        val partial = File(updateDirectory, "FengWo.apk.part").apply { writeText("partial") }
        assertNull(AppUpdatePackagePolicy.resolveApk(temporary.root, partial.path))
        val outside = temporary.newFile("other.apk").apply { writeText("other") }
        assertNull(AppUpdatePackagePolicy.resolveApk(temporary.root, outside.path))
        val empty = File(updateDirectory, "empty.apk").apply { createNewFile() }
        assertNull(AppUpdatePackagePolicy.resolveApk(temporary.root, empty.path))
        assertNull(AppUpdatePackagePolicy.resolveApk(temporary.root, File(updateDirectory, "gone.apk").path))
    }

    @Test
    fun rejectsSymlinkEscapingUpdateCache() {
        val root = temporary.newFolder("fengwo-app-updates")
        val outside = temporary.newFile("outside.apk").apply { writeText("outside") }
        val link = File(root, "FengWo.apk")
        Files.createSymbolicLink(link.toPath(), outside.toPath())
        assertNull(AppUpdatePackagePolicy.resolveApk(temporary.root, link.path))
    }

    @Test
    fun rejectsUpdateRootRedirectedOutsideCache() {
        val external = temporary.newFolder("external")
        val apk = File(external, "FengWo.apk").apply { writeText("apk") }
        val root = File(temporary.root, "fengwo-app-updates")
        Files.createSymbolicLink(root.toPath(), external.toPath())
        assertNull(AppUpdatePackagePolicy.resolveApk(temporary.root, File(root, apk.name).path))
    }

    @Test
    fun acceptsOnlyNewerOwnPackageWithCompatibleSigning() {
        assertTrue(accepts())
        assertFalse(accepts(candidatePackage = "other.app"))
        assertFalse(accepts(candidateVersion = 104))
        assertFalse(accepts(candidateVersion = 103))
        assertFalse(accepts(candidateSigners = emptySet(), candidateHistory = emptySet()))
        assertFalse(accepts(candidateSigners = setOf("other"), candidateHistory = setOf("other")))
    }

    @Test
    fun allowsVerifiedSingleSignerRotationButNotPartialMultipleSigners() {
        assertTrue(accepts(candidateSigners = setOf("next"), candidateHistory = setOf("current", "next")))
        assertFalse(accepts(candidateSigners = setOf("current", "other")))
        assertFalse(accepts(installedSigners = setOf("current", "other")))
        assertTrue(accepts(installedSigners = setOf("current", "other"), candidateSigners = setOf("current", "other")))
    }

    private fun accepts(
        candidatePackage: String = "com.fengwo.accelerator",
        candidateVersion: Long = 105,
        installedSigners: Set<String> = setOf("current"),
        candidateSigners: Set<String> = setOf("current"),
        candidateHistory: Set<String> = candidateSigners,
    ): Boolean = AppUpdatePackagePolicy.accepts(
        installedPackage = "com.fengwo.accelerator",
        candidatePackage = candidatePackage,
        installedVersion = 104,
        candidateVersion = candidateVersion,
        installedSigners = installedSigners,
        candidateSigners = candidateSigners,
        candidateHistory = candidateHistory,
    )
}
