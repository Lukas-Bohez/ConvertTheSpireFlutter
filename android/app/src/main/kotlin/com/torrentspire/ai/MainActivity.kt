package com.torrentspire.ai

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.os.Environment
import android.media.MediaScannerConnection
import android.util.Rational
import androidx.documentfile.provider.DocumentFile
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import androidx.core.content.ContextCompat
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream

class MainActivity : AudioServiceActivity() {
    private val channelName = "convert_the_spire/saf"
    private val pickTreeRequestCode = 5011
    private var pendingResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Enable edge-to-edge display for modern Android (requires androidx.core)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            WindowCompat.setDecorFitsSystemWindows(window, false)
        }
        super.onCreate(savedInstanceState)
    }

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
                                    result.error("COPY_FAILED", e.localizedMessage, null)
                                }
                            }
                        }.start()
                    }
                    "testTreeWrite" -> {
                        val treeUri = call.argument<String>("treeUri")
                        if (treeUri.isNullOrBlank()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        Thread {
                            val ok = tryTestTreeWrite(treeUri)
                            runOnUiThread { result.success(ok) }
                        }.start()
                    }
                    "openTree" -> {
                        val treeUri = call.argument<String>("treeUri")
                        if (treeUri.isNullOrBlank()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val ok = openTreeUri(treeUri)
                        result.success(ok)
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
                                val dest = copyToPublicDownloads(sourcePath, displayName, mimeType, subdir)
                                runOnUiThread { result.success(dest) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("COPY_DOWNLOADS_FAILED", e.localizedMessage, null) }
                            }
                        }.start()
                    }
                    "copyToTemp" -> {
                        val uriString = call.argument<String>("uri")
                        if (uriString.isNullOrBlank()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val copied = copyContentUriToTemp(uriString)
                                runOnUiThread { result.success(copied) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("COPY_TEMP_FAILED", e.localizedMessage, null) }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == pickTreeRequestCode) {
            val result = pendingResult
            pendingResult = null
            if (result == null) return
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                result.success(null)
                return
            }
            val treeUri = data.data!!
            try {
                contentResolver.takePersistableUriPermission(
                    treeUri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            } catch (_: SecurityException) {
            }
            result.success(treeUri.toString())
        }
    }

    private fun copyFileToTree(treeUriString: String, sourcePath: String, displayName: String, mimeType: String, subdir: String?): Uri? {
        val treeUri = Uri.parse(treeUriString)
        val root = DocumentFile.fromTreeUri(this, treeUri) ?: return null
        var targetDir = root
        if (!subdir.isNullOrBlank()) {
            val existing = root.findFile(subdir)
            targetDir = existing ?: root.createDirectory(subdir) ?: root
        }
        val targetName = displayName
        val existing = targetDir.findFile(targetName)
        existing?.delete()
        val newFile = targetDir.createFile(mimeType, targetName) ?: return null
        contentResolver.openOutputStream(newFile.uri)?.use { out ->
            FileInputStream(File(sourcePath)).use { input ->
                input.copyTo(out)
            }
        } ?: return null
        MediaScannerConnection.scanFile(this, arrayOf(sourcePath), null, null)
        return newFile.uri
    }

    private fun tryTestTreeWrite(treeUriString: String): Boolean {
        return try {
            val treeUri = Uri.parse(treeUriString)
            val root = DocumentFile.fromTreeUri(this, treeUri) ?: return false
            val probeName = ".write_probe_${System.currentTimeMillis()}.tmp"
            val probe = root.createFile("application/octet-stream", probeName) ?: return false
            val ok = contentResolver.openOutputStream(probe.uri)?.use { out ->
                out.write(byteArrayOf(0x57, 0x54, 0x53))
                out.flush()
                true
            } ?: false
            probe.delete()
            ok
        } catch (_: Exception) {
            false
        }
    }

    private fun openTreeUri(treeUriString: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse(treeUriString)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun copyToPublicDownloads(sourcePath: String, displayName: String, mimeType: String, subdir: String?): String? {
        val src = File(sourcePath)
        if (!src.exists()) return null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH,
                    if (subdir.isNullOrBlank()) Environment.DIRECTORY_DOWNLOADS
                    else Environment.DIRECTORY_DOWNLOADS + File.separator + subdir
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            val uri = contentResolver.insert(collection, values) ?: return null
            contentResolver.openOutputStream(uri)?.use { out ->
                FileInputStream(src).use { input -> input.copyTo(out) }
            }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            return uri.toString()
        }

        val base = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val targetDir = if (subdir.isNullOrBlank()) base else File(base, subdir)
        if (!targetDir.exists()) targetDir.mkdirs()
        val target = File(targetDir, displayName)
        FileInputStream(src).use { input ->
            FileOutputStream(target).use { out -> input.copyTo(out) }
        }
        MediaScannerConnection.scanFile(this, arrayOf(target.absolutePath), null, null)
        return target.absolutePath
    }

    private fun copyContentUriToTemp(uriString: String): String? {
        val srcUri = Uri.parse(uriString)
        val tempFile = File.createTempFile("saf_", null, cacheDir)
        contentResolver.openInputStream(srcUri)?.use { input ->
            FileOutputStream(tempFile).use { output -> input.copyTo(output) }
        } ?: return null
        return tempFile.absolutePath
    }

    // Picture-in-Picture support: called when user navigates away while video is playing
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                // Request PiP mode with 16:9 aspect ratio for video content
                val pipParams = PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(16, 9))
                    .build()
                enterPictureInPictureMode(pipParams)
            } catch (e: Exception) {
                // If PiP fails, continue with normal behavior
                e.printStackTrace()
            }
        }
    }
}
