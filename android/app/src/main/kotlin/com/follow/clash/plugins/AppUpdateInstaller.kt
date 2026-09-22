package com.follow.clash.plugins

import android.app.Activity
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.core.content.pm.PackageInfoCompat
import androidx.core.net.toUri
import java.io.File

internal class AppUpdateInstaller(private val context: Context) {
    @Suppress("DEPRECATION")
    fun validate(path: String): File? {
        val file = AppUpdatePackagePolicy.resolveApk(context.cacheDir, path) ?: return null
        val manager = context.packageManager
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        val candidate = manager.getPackageArchiveInfo(file.path, flags) ?: return null
        val installed = manager.getPackageInfo(context.packageName, flags)
        val candidateSigners = signers(candidate)
        val candidateHistory = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            candidate.signingInfo?.signingCertificateHistory?.map { it.toCharsString() }?.toSet()
                ?: candidateSigners
        } else {
            candidateSigners
        }
        return file.takeIf {
            AppUpdatePackagePolicy.accepts(
                installedPackage = context.packageName,
                candidatePackage = candidate.packageName,
                installedVersion = PackageInfoCompat.getLongVersionCode(installed),
                candidateVersion = PackageInfoCompat.getLongVersionCode(candidate),
                installedSigners = signers(installed),
                candidateSigners = candidateSigners,
                candidateHistory = candidateHistory,
            )
        }
    }

    @Suppress("DEPRECATION")
    fun open(activity: Activity, file: File, requestCode: Int): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !context.packageManager.canRequestPackageInstalls()
        ) {
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                    data = "package:${context.packageName}".toUri()
                },
            )
            return "permissionRequired"
        }
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.app_updates",
            file,
        )
        activity.startActivityForResult(
            Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                putExtra(Intent.EXTRA_RETURN_RESULT, true)
                clipData = ClipData.newRawUri("FengWo update", uri)
            },
            requestCode,
        )
        return null
    }

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners
        } else {
            info.signatures
        }
        return signatures?.map { it.toCharsString() }?.toSet() ?: emptySet()
    }
}
