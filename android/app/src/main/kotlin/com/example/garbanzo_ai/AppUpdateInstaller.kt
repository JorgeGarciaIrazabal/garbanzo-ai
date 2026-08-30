package com.example.garbanzo_ai

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

/** Bridges Flutter's downloaded APK into Android's user-confirmed package installer. */
class AppUpdateInstaller(
    private val activity: FlutterActivity,
    messenger: BinaryMessenger,
) {
    companion object {
        private const val CHANNEL = "com.example.garbanzo_ai/app_update"
    }

    private val statusAction = "${activity.packageName}.APP_UPDATE_STATUS"
    private val channel = MethodChannel(messenger, CHANNEL)
    private var pendingResult: MethodChannel.Result? = null

    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
                PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                    confirmationIntent(intent)?.let(activity::startActivity)
                        ?: finishWithError("Android did not provide an install confirmation")
                }
                PackageInstaller.STATUS_SUCCESS -> {
                    pendingResult?.success(null)
                    pendingResult = null
                }
                else -> finishWithError(
                    intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                        ?: "Android rejected the update",
                )
            }
        }
    }

    init {
        registerStatusReceiver()
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureInstallPermission" -> ensureInstallPermission(result)
                "installApk" -> installApk(call.arguments as? String, result)
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        try {
            activity.unregisterReceiver(statusReceiver)
        } catch (_: IllegalArgumentException) {
            // Already unregistered during activity teardown.
        }
    }

    private fun ensureInstallPermission(result: MethodChannel.Result) {
        if (canRequestInstalls()) {
            result.success(true)
            return
        }
        activity.startActivity(
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}"),
            ),
        )
        result.success(false)
    }

    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (!canRequestInstalls()) {
            result.error("install_permission_required", "Install permission is required", null)
            return
        }
        if (pendingResult != null) {
            result.error("install_in_progress", "An Android update is already being installed", null)
            return
        }
        val apk = path?.let(::File)
        if (apk == null || !apk.isFile || apk.length() == 0L) {
            result.error("invalid_apk", "The downloaded APK is missing or empty", null)
            return
        }

        try {
            verifyPackage(apk)
        } catch (error: Exception) {
            result.error("invalid_apk", error.message ?: "APK verification failed", null)
            return
        }

        pendingResult = result
        Thread {
            try {
                commitPackage(apk)
            } catch (error: Exception) {
                activity.runOnUiThread {
                    finishWithError(error.message ?: "Could not start Android's installer")
                }
            }
        }.start()
    }

    private fun commitPackage(apk: File) {
        val installer = activity.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            .apply { setAppPackageName(activity.packageName) }
        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            FileInputStream(apk).use { input ->
                session.openWrite("base.apk", 0, apk.length()).use { output ->
                    input.copyTo(output, 1024 * 1024)
                    session.fsync(output)
                }
            }
            val callback = Intent(statusAction).setPackage(activity.packageName)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
            val sender = PendingIntent.getBroadcast(activity, sessionId, callback, flags).intentSender
            session.commit(sender)
        }
        apk.delete()
        apk.parentFile?.delete()
    }

    @Suppress("DEPRECATION")
    private fun verifyPackage(apk: File) {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        val archive = activity.packageManager.getPackageArchiveInfo(apk.path, flags)
            ?: error("Android could not read the downloaded APK")
        if (archive.packageName != activity.packageName) {
            error("The APK is for ${archive.packageName}, not ${activity.packageName}")
        }
        val installed = activity.packageManager.getPackageInfo(activity.packageName, flags)
        if (versionCode(archive) <= versionCode(installed)) {
            error("The downloaded APK is not newer than the installed app")
        }
        if (signerDigests(archive).intersect(signerDigests(installed)).isEmpty()) {
            error("The APK was signed with a different certificate")
        }
    }

    @Suppress("DEPRECATION")
    private fun signerDigests(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = info.signingInfo ?: return emptySet()
            if (signingInfo.hasMultipleSigners()) {
                signingInfo.apkContentsSigners
            } else {
                signingInfo.signingCertificateHistory
            }
        } else {
            info.signatures.orEmpty()
        }
        return signatures.mapTo(mutableSetOf()) { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).toHex()
        }
    }

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
        else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun confirmationIntent(status: Intent): Intent? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            status.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        } else {
            status.getParcelableExtra(Intent.EXTRA_INTENT)
        }

    private fun finishWithError(message: String) {
        pendingResult?.error("install_failed", message, null)
        pendingResult = null
    }

    private fun registerStatusReceiver() {
        val filter = IntentFilter(statusAction)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(statusReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            activity.registerReceiver(statusReceiver, filter)
        }
    }

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

    private fun canRequestInstalls(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            activity.packageManager.canRequestPackageInstalls()
}
