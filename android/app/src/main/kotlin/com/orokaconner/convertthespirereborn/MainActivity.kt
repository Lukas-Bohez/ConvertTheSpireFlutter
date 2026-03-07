package com.orokaconner.convertthespirereborn

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private val channelName = "convert_the_spire/saf"
    private val pickTreeRequestCode = 5011
    private var pendingResult: MethodChannel.Result? = null

    // Screencast
    private val screenCaptureRequestCode = 5020
    private val audioPermissionRequestCode = 5021
    private var screencastResult: MethodChannel.Result? = null
    private var audioPermissionGranted = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickTree" -> {
                        if (pendingResult != null) {
                            result.error("BUSY", "Folder picker already in progress", null)
                            return@setMethodCallHandler
                        }
                        pendingResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                            )
                        }
                        startActivityForResult(intent, pickTreeRequestCode)
                    }
                    "copyToTree" -> {
                        val treeUri = call.argument<String>("treeUri")
                        val sourcePath = call.argument<String>("sourcePath")
                        val displayName = call.argument<String>("displayName")
                        val mimeType = call.argument<String>("mimeType")
                        val subdir = call.argument<String>("subdir")
                        if (treeUri.isNullOrBlank() || sourcePath.isNullOrBlank() || displayName.isNullOrBlank() || mimeType.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "Missing arguments", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val destUri = copyFileToTree(treeUri, sourcePath, displayName, mimeType, subdir)
                                runOnUiThread {
                                    result.success(destUri?.toString())
                                }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("COPY_FAILED", e.message, null)
                                }
                            }
                        }.start()
                    }
                    "openTree" -> {
                        try {
                            val treeUri = call.argument<String>("treeUri")
                            if (treeUri.isNullOrBlank()) {
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(Uri.parse(treeUri), "vnd.android.document/directory")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "copyToDownloads" -> {
                        val sourcePath = call.argument<String>("sourcePath")
                        val displayName = call.argument<String>("displayName")
                        val mimeType = call.argument<String>("mimeType")
                        val subdir = call.argument<String>("subdir")
                        if (sourcePath.isNullOrBlank() || displayName.isNullOrBlank() || mimeType.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "Missing arguments", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val destUri = copyFileToDownloads(sourcePath, displayName, mimeType, subdir)
                                runOnUiThread {
                                    result.success(destUri?.toString())
                                }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("COPY_FAILED", e.message, null)
                                }
                            }
                        }.start()
                    }
                    "listTree" -> {
                        val treeUri = call.argument<String>("treeUri")
                        if (treeUri.isNullOrBlank()) {
                            result.success(emptyList<Map<String, String>>())
                            return@setMethodCallHandler
                        }
                        try {
                            val tree = DocumentFile.fromTreeUri(this, Uri.parse(treeUri))
                            val out = mutableListOf<Map<String, String>>()
                            fun recurse(dir: DocumentFile?) {
                                if (dir == null) return
                                for (f in dir.listFiles()) {
                                    if (f.isDirectory) {
                                        recurse(f)
                                    } else {
                                        val mime = try {
                                            contentResolver.getType(f.uri) ?: ""
                                        } catch (_: Exception) { "" }
                                        out.add(mapOf(
                                            "uri" to f.uri.toString(),
                                            "name" to (f.name ?: ""),
                                            "mime" to mime
                                        ))
                                    }
                                }
                            }
                            recurse(tree)
                            result.success(out)
                        } catch (e: Exception) {
                            result.error("LIST_FAILED", e.message, null)
                        }
                    }
                    "copyToTemp" -> {
                        val uriStr = call.argument<String>("uri")
                        if (uriStr.isNullOrBlank()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        try {
                            val srcUri = Uri.parse(uriStr)
                            val input = contentResolver.openInputStream(srcUri)
                            val name = DocumentFile.fromSingleUri(this, srcUri)?.name ?: "tmp"
                            val dest = File(cacheDir, "saf_tmp_${System.currentTimeMillis()}_$name")
                            input?.use { ins ->
                                dest.outputStream().use { out ->
                                    ins.copyTo(out)
                                }
                            }
                            result.success(dest.absolutePath)
                        } catch (e: Exception) {
                            result.error("COPY_FAILED", e.message, null)
                        }
                    }
                    "getFilesDir" -> {
                        result.success(filesDir.absolutePath)
                    }
                    "getCacheDir" -> {
                        result.success(cacheDir.absolutePath)
                    }
                    "getExternalFilesDir" -> {
                        val dir = getExternalFilesDir(null)
                        result.success(dir?.absolutePath)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Screencast channel ──────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "convert_the_spire/screencast")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> {
                        if (screencastResult != null) {
                            result.error("BUSY", "Permission request already in progress", null)
                            return@setMethodCallHandler
                        }
                        screencastResult = result
                        // Check RECORD_AUDIO first (needed for system audio capture)
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
                            == PackageManager.PERMISSION_GRANTED) {
                            audioPermissionGranted = true
                            launchMediaProjectionRequest()
                        } else {
                            ActivityCompat.requestPermissions(
                                this, arrayOf(Manifest.permission.RECORD_AUDIO),
                                audioPermissionRequestCode
                            )
                        }
                    }
                    "startCapture" -> {
                        val width = call.argument<Int>("width") ?: 1920
                        val height = call.argument<Int>("height") ?: 1080
                        val fps = call.argument<Int>("fps") ?: 30
                        ScreenCaptureService.lastError = null
                        val intent = Intent(this, ScreenCaptureService::class.java).apply {
                            action = ScreenCaptureService.ACTION_START
                            putExtra("width", width)
                            putExtra("height", height)
                            putExtra("fps", fps)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        // Poll until service is ready
                        var attempts = 0
                        val handler = Handler(Looper.getMainLooper())
                        fun checkReady() {
                            if (ScreenCaptureService.isRunning && ScreenCaptureService.streamPort > 0) {
                                result.success(ScreenCaptureService.streamPort)
                            } else if (ScreenCaptureService.lastError != null) {
                                result.error("START_FAILED", ScreenCaptureService.lastError, null)
                            } else if (attempts++ < 20) {
                                handler.postDelayed(::checkReady, 250)
                            } else {
                                result.error("TIMEOUT", "Capture service did not start", null)
                            }
                        }
                        handler.postDelayed(::checkReady, 500)
                    }
                    "stopCapture" -> {
                        val intent = Intent(this, ScreenCaptureService::class.java).apply {
                            action = ScreenCaptureService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(null)
                    }
                    "isCapturing" -> {
                        result.success(ScreenCaptureService.isRunning)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun launchMediaProjectionRequest() {
        val mgr = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(mgr.createScreenCaptureIntent(), screenCaptureRequestCode)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode == audioPermissionRequestCode) {
            audioPermissionGranted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            launchMediaProjectionRequest()
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == screenCaptureRequestCode) {
            val res = screencastResult
            screencastResult = null
            if (resultCode == Activity.RESULT_OK && data != null) {
                ScreenCaptureService.resultCode = resultCode
                ScreenCaptureService.resultData = data
                ScreenCaptureService.audioGranted = audioPermissionGranted
                res?.success(mapOf("granted" to true, "audio" to audioPermissionGranted))
            } else {
                res?.success(mapOf("granted" to false, "audio" to false))
            }
            return
        }
        if (requestCode == pickTreeRequestCode) {
            val result = pendingResult
            pendingResult = null
            if (result == null) {
                return
            }
            if (resultCode != Activity.RESULT_OK || data == null) {
                result.success(null)
                return
            }
            val uri = data.data
            if (uri == null) {
                result.success(null)
                return
            }
            try {
                val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                contentResolver.takePersistableUriPermission(uri, flags)
            } catch (_: Exception) {
            }
            result.success(uri.toString())
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun copyFileToTree(
        treeUri: String,
        sourcePath: String,
        displayName: String,
        mimeType: String,
        subdir: String?,
    ): Uri? {
        val tree = DocumentFile.fromTreeUri(this, Uri.parse(treeUri)) ?: return null
        val targetDir = if (subdir.isNullOrBlank()) {
            tree
        } else {
            tree.findFile(subdir) ?: tree.createDirectory(subdir) ?: tree
        }

        targetDir.findFile(displayName)?.delete()
        val destFile = targetDir.createFile(mimeType, displayName) ?: return null

        contentResolver.openOutputStream(destFile.uri, "w")?.use { output ->
            FileInputStream(File(sourcePath)).use { input ->
                input.copyTo(output)
            }
        }
        return destFile.uri
    }

    private fun copyFileToDownloads(
        sourcePath: String,
        displayName: String,
        mimeType: String,
        subdir: String?,
    ): Uri? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return null
        }

        val relativeBase = if (subdir.isNullOrBlank()) {
            "Download/ConvertTheSpireReborn"
        } else {
            "Download/ConvertTheSpireReborn/$subdir"
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativeBase)
        }
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val uri = contentResolver.insert(collection, values) ?: return null

        contentResolver.openOutputStream(uri, "w")?.use { output ->
            FileInputStream(File(sourcePath)).use { input ->
                input.copyTo(output)
            }
        } ?: return null

        return uri
    }
}
