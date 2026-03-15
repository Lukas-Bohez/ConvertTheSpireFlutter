package com.orokaconner.convertthespirereborn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class ForegroundDownloadService : Service() {
    companion object {
        const val CHANNEL_ID = "cts_foreground_channel"
        const val NOTIF_ID = 0xF00D
        const val ACTION_START = "com.orokaconner.convertthespirereborn.action.START_DOWNLOAD_SERVICE"
        const val ACTION_STOP = "com.orokaconner.convertthespirereborn.action.STOP_DOWNLOAD_SERVICE"

        fun createStartIntent(context: Context): Intent =
            Intent(context, ForegroundDownloadService::class.java).apply { action = ACTION_START }

        fun createStopIntent(context: Context): Intent =
            Intent(context, ForegroundDownloadService::class.java).apply { action = ACTION_STOP }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startForeground(NOTIF_ID, buildNotification())
            ACTION_STOP -> {
                stopForeground(true)
                stopSelf()
            }
            else -> {
                // If the service is started without explicit action, ensure it is foreground
                startForeground(NOTIF_ID, buildNotification())
            }
        }
        return START_STICKY
    }

    private fun buildNotification(): android.app.Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingOpen = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
        )

        val stopIntent = createStopIntent(this)
        val pendingStop = PendingIntent.getService(
            this,
            1,
            stopIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Convert the Spire — Downloads")
            .setContentText("Downloads in progress")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentIntent(pendingOpen)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", pendingStop)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Convert the Spire background"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = "Notifications for background downloads and long-running tasks"
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }
}
