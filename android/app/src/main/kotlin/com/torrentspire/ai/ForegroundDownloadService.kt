package com.torrentspire.ai

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * Keeps the process alive while downloads run.
 *
 * Without this, Android freezes the app shortly after the screen goes off and
 * downloads stall silently (issue #7). A plain notification is not enough -
 * only a foreground service keeps the process scheduled.
 *
 * The notification text is supplied by Dart, which knows the build flavour and
 * the user language; this class never hard-codes a product name.
 */
class ForegroundDownloadService : Service() {
    companion object {
        const val CHANNEL_ID = "cts_foreground_channel"
        const val NOTIF_ID = 0xF00D
        const val ACTION_START = "com.torrentspire.ai.action.START_DOWNLOAD_SERVICE"
        const val ACTION_STOP = "com.torrentspire.ai.action.STOP_DOWNLOAD_SERVICE"
        const val ACTION_UPDATE = "com.torrentspire.ai.action.UPDATE_DOWNLOAD_SERVICE"

        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_PROGRESS = "progress"
        const val EXTRA_CHANNEL_NAME = "channelName"

        /**
         * Set by MainActivity so the Stop action can reach Dart. Null when no
         * engine is attached, in which case stopping is all we can do.
         */
        @Volatile
        @JvmStatic
        var onStopRequested: (() -> Unit)? = null

        fun createStartIntent(context: Context): Intent =
            Intent(context, ForegroundDownloadService::class.java).apply { action = ACTION_START }

        fun createStopIntent(context: Context): Intent =
            Intent(context, ForegroundDownloadService::class.java).apply { action = ACTION_STOP }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var started = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel(null)
        acquireLocks()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                notifyDartStopRequested()
                stopEverything()
                return START_NOT_STICKY
            }
            ACTION_UPDATE -> {
                if (started) {
                    notificationManager().notify(NOTIF_ID, buildNotification(intent))
                } else {
                    goForeground(intent)
                }
            }
            else -> goForeground(intent)
        }

        // Deliberately NOT sticky: a sticky restart after a process kill brings
        // the service back without a Flutter engine, leaving a "downloading"
        // notification with nothing behind it.
        return START_NOT_STICKY
    }

    /**
     * Android 15+ caps dataSync foreground services at 6 hours per 24. When the
     * cap is hit we must stop promptly or the system kills the app.
     */
    override fun onTimeout(startId: Int, fgsType: Int) {
        Log.w("ForegroundDownload", "foreground service timed out; pausing queue")
        notifyDartStopRequested()
        stopEverything()
    }

    override fun onDestroy() {
        releaseLocks()
        super.onDestroy()
    }

    private fun goForeground(intent: Intent?) {
        createNotificationChannel(intent?.getStringExtra(EXTRA_CHANNEL_NAME))
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        } else {
            0
        }
        // targetSdk is 36, so starting without a declared type throws on
        // Android 14+.
        ServiceCompat.startForeground(this, NOTIF_ID, buildNotification(intent), type)
        started = true
    }

    private fun stopEverything() {
        started = false
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        releaseLocks()
        stopSelf()
    }

    private fun notifyDartStopRequested() {
        val callback = onStopRequested ?: return
        // Method channels must be used from the main thread.
        Handler(Looper.getMainLooper()).post {
            try {
                callback()
            } catch (e: Exception) {
                Log.w("ForegroundDownload", "stop callback failed: " + e.message)
            }
        }
    }

    private fun acquireLocks() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "ConvertTheSpire:downloads"
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (e: Exception) {
            Log.w("ForegroundDownload", "wake lock unavailable: " + e.message)
        }
        try {
            val wifiManager =
                applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                WifiManager.WIFI_MODE_FULL_LOW_LATENCY
            } else {
                @Suppress("DEPRECATION")
                WifiManager.WIFI_MODE_FULL_HIGH_PERF
            }
            wifiLock = wifiManager.createWifiLock(mode, "ConvertTheSpire:downloads").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (e: Exception) {
            Log.w("ForegroundDownload", "wifi lock unavailable: " + e.message)
        }
    }

    private fun releaseLocks() {
        try {
            wakeLock?.takeIf { it.isHeld }?.release()
        } catch (e: Exception) {
            Log.w("ForegroundDownload", "wake lock release failed: " + e.message)
        }
        wakeLock = null
        try {
            wifiLock?.takeIf { it.isHeld }?.release()
        } catch (e: Exception) {
            Log.w("ForegroundDownload", "wifi lock release failed: " + e.message)
        }
        wifiLock = null
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun buildNotification(intent: Intent?): android.app.Notification {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Downloads"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Downloading"
        val progress = intent?.getIntExtra(EXTRA_PROGRESS, -1) ?: -1

        val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingOpen = PendingIntent.getActivity(this, 0, openIntent, pendingFlags)
        val pendingStop =
            PendingIntent.getService(this, 1, createStopIntent(this), pendingFlags)

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentIntent(pendingOpen)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", pendingStop)
            .setOnlyAlertOnce(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setOngoing(true)

        if (progress in 0..100) {
            builder.setProgress(100, progress, false)
        } else {
            builder.setProgress(0, 0, true)
        }
        return builder.build()
    }

    private fun createNotificationChannel(channelName: String?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            channelName ?: "Downloads",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            setShowBadge(false)
        }
        notificationManager().createNotificationChannel(channel)
    }
}
