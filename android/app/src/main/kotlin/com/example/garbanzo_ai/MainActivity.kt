package com.example.garbanzo_ai

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.database.Cursor
import android.media.audiofx.AcousticEchoCanceler
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val TALK_AUDIO_CHANNEL = "com.example.garbanzo_ai/talk_audio"
        private const val SHARED_CONTENT_CHANNEL = "com.example.garbanzo_ai/shared_content"
        // One byte over the largest supported attachment is enough for the
        // Flutter validator to identify it as oversized without reading an
        // arbitrarily large shared video/archive into memory.
        private const val MAX_SHARED_BYTES = 20 * 1024 * 1024 + 1
    }

    private lateinit var sharedContentChannel: MethodChannel
    private lateinit var appUpdateInstaller: AppUpdateInstaller

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        appUpdateInstaller = AppUpdateInstaller(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TALK_AUDIO_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAcousticEchoCancelerAvailable" ->
                    result.success(AcousticEchoCanceler.isAvailable())
                else -> result.notImplemented()
            }
        }
        sharedContentChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARED_CONTENT_CHANNEL,
        )
        sharedContentChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialShare" -> result.success(consumeShareIntent(intent))
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        if (::appUpdateInstaller.isInitialized) appUpdateInstaller.dispose()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // If the engine is still starting, leave the intent untouched so
        // Flutter's getInitialShare call can consume it once the channel exists.
        if (!::sharedContentChannel.isInitialized) return
        val content = consumeShareIntent(intent) ?: return
        sharedContentChannel.invokeMethod("sharedContent", content)
    }

    private fun consumeShareIntent(shareIntent: Intent?): Map<String, Any?>? {
        if (shareIntent == null ||
            (shareIntent.action != Intent.ACTION_SEND &&
                shareIntent.action != Intent.ACTION_SEND_MULTIPLE)
        ) {
            return null
        }

        val uris = sharedUris(shareIntent)
        val files = uris.mapNotNull(::readSharedFile)
        val text = shareIntent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()

        // The Activity is singleTop, so consume each intent exactly once even
        // if Flutter asks for the initial payload again after a hot restart.
        shareIntent.action = null
        if (files.isEmpty() && text.isNullOrBlank()) return null
        return mapOf("files" to files, "text" to text)
    }

    @Suppress("DEPRECATION")
    private fun sharedUris(shareIntent: Intent): List<Uri> {
        val uris = when (shareIntent.action) {
            Intent.ACTION_SEND_MULTIPLE ->
                shareIntent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM).orEmpty()
            Intent.ACTION_SEND ->
                listOfNotNull(shareIntent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
            else -> emptyList()
        }.toMutableList()

        val clipData = shareIntent.clipData
        if (clipData != null) {
            for (index in 0 until clipData.itemCount) {
                clipData.getItemAt(index).uri?.let(uris::add)
            }
        }
        return uris.distinct()
    }

    private fun readSharedFile(uri: Uri): Map<String, Any>? {
        return try {
            val bytes = contentResolver.openInputStream(uri)?.use(::readSharedBytes)
                ?: return null
            mapOf(
                "name" to (displayName(uri) ?: uri.lastPathSegment ?: "shared-file"),
                "bytes" to bytes,
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun readSharedBytes(input: java.io.InputStream): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (output.size() < MAX_SHARED_BYTES) {
            val remaining = MAX_SHARED_BYTES - output.size()
            val count = input.read(buffer, 0, minOf(buffer.size, remaining))
            if (count < 0) break
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    private fun displayName(uri: Uri): String? {
        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )
            if (cursor?.moveToFirst() == true) cursor?.getString(0) else null
        } finally {
            cursor?.close()
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return

        nm.createNotificationChannel(
            NotificationChannel(
                "chat_responses",
                "Chat responses",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Assistant replies that arrive while the app is in the background."
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(
                "reminders",
                "Reminders",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Scheduled reminders and recurring check-ins."
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(
                "system_alerts",
                "System alerts",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Account, security, and other system notifications."
            }
        )
    }
}
