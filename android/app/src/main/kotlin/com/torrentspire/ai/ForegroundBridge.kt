package com.torrentspire.ai

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Dart side of the download keep-alive: `convert_the_spire/foreground`.
 *
 * Holds only the application context, never the activity. audio_service keeps
 * the Flutter engine alive after MainActivity is destroyed, so downloads keep
 * running when the user backs out of the app. This channel has to keep
 * working then too, or Dart could never stop the service and it would hold
 * its wake lock until the process died.
 */
class ForegroundBridge(context: Context, messenger: BinaryMessenger) {
    private val appContext = context.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler { call, result -> onMethodCall(call, result) }
        // The notification's Stop action has to pause the Dart-side work, not
        // just dismiss the notification.
        ForegroundDownloadService.onStopRequested = {
            channel.invokeMethod("pauseDownloads", null)
        }
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startForegroundService" -> result.success(start(call))
            "updateForegroundService" -> result.success(update(call))
            "stopForegroundService" -> result.success(stop())
            "isIgnoringBatteryOptimizations" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                    result.success(true)
                } else {
                    val pm = appContext.getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(appContext.packageName))
                }
            }
            "deviceName" -> result.success(resolveDeviceName())
            else -> result.notImplemented()
        }
    }

    private fun start(call: MethodCall): Boolean {
        return try {
            val intent = Intent(appContext, ForegroundDownloadService::class.java).apply {
                action = ForegroundDownloadService.ACTION_START
                putExtra(ForegroundDownloadService.EXTRA_TITLE, call.argument<String>("title"))
                putExtra(ForegroundDownloadService.EXTRA_TEXT, call.argument<String>("text"))
                putExtra(
                    ForegroundDownloadService.EXTRA_PROGRESS,
                    call.argument<Int>("progress") ?: -1
                )
                putExtra(
                    ForegroundDownloadService.EXTRA_CHANNEL_NAME,
                    call.argument<String>("channelName")
                )
            }
            ContextCompat.startForegroundService(appContext, intent)
            true
        } catch (e: Exception) {
            // Android 12+ refuses to start a foreground service from the
            // background. Dart retries on its next update.
            Log.w(TAG, "start failed: " + e.message)
            false
        }
    }

    /**
     * Updates the running notification in place. Going through
     * startForegroundService once a second would be refused while the app is
     * in the background, which is exactly when the notification matters.
     */
    private fun update(call: MethodCall): Boolean {
        if (!ForegroundDownloadService.isRunning) return start(call)
        return try {
            ForegroundDownloadService.postNotification(
                appContext,
                call.argument<String>("title"),
                call.argument<String>("text"),
                call.argument<Int>("progress") ?: -1
            )
            true
        } catch (e: Exception) {
            Log.w(TAG, "update failed: " + e.message)
            false
        }
    }

    /**
     * stopService, not a stop intent: an intent would start the service just
     * to stop it, and it is how the notification's own Stop button reports
     * back to Dart. A stop that Dart asked for must not echo back as a
     * request to pause everything.
     */
    private fun stop(): Boolean {
        return try {
            appContext.stopService(Intent(appContext, ForegroundDownloadService::class.java))
            true
        } catch (e: Exception) {
            Log.w(TAG, "stop failed: " + e.message)
            false
        }
    }

    /**
     * A human-readable name for this device, used as the default Watch
     * Together display name. Settings.Global.DEVICE_NAME is what the user
     * actually set; Build.MODEL is the fallback.
     */
    private fun resolveDeviceName(): String {
        try {
            val name = Settings.Global.getString(appContext.contentResolver, "device_name")
            if (!name.isNullOrBlank()) return name
        } catch (e: Exception) {
            Log.w(TAG, "device name unavailable: " + e.message)
        }
        val manufacturer = Build.MANUFACTURER ?: ""
        val model = Build.MODEL ?: ""
        return when {
            model.startsWith(manufacturer, ignoreCase = true) -> model
            manufacturer.isBlank() -> model
            else -> (manufacturer + " " + model).trim()
        }
    }

    companion object {
        private const val CHANNEL = "convert_the_spire/foreground"
        private const val TAG = "ForegroundBridge"
    }
}
