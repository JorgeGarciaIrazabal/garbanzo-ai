package com.example.garbanzo_ai

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
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
