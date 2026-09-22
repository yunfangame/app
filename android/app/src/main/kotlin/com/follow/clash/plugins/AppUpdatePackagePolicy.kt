package com.follow.clash.plugins

import java.io.File

internal object AppUpdatePackagePolicy {
    fun resolveApk(cacheDirectory: File, path: String): File? {
        val expectedRoot = File(cacheDirectory.canonicalFile, "fengwo-app-updates")
        val root = expectedRoot.canonicalFile
        if (root != expectedRoot) return null
        val file = File(path).canonicalFile
        if (!file.path.startsWith(root.path + File.separator) ||
            !file.isFile || !file.canRead() || file.length() <= 0 ||
            !file.extension.equals("apk", ignoreCase = true)
        ) {
            return null
        }
        return file
    }

    fun accepts(
        installedPackage: String,
        candidatePackage: String,
        installedVersion: Long,
        candidateVersion: Long,
        installedSigners: Set<String>,
        candidateSigners: Set<String>,
        candidateHistory: Set<String>,
    ): Boolean {
        if (installedPackage != candidatePackage || candidateVersion <= installedVersion ||
            installedSigners.isEmpty() || candidateSigners.isEmpty()
        ) {
            return false
        }
        if (installedSigners == candidateSigners) return true
        return installedSigners.size == 1 && candidateSigners.size == 1 &&
            candidateHistory.containsAll(installedSigners)
    }
}
