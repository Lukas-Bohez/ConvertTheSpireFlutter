package com.orokaconner.convertthespirereborn

import android.app.Activity
import android.content.Intent
import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.os.Environment
import android.media.MediaScannerConnection
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.ContextCompat
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private val channelName = "convert_the_spire/saf"
    private val pickTreeRequestCode = 5011
    private var pendingResult: MethodChannel.Result? = null

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
                    "testTreeWrite" -> {
                        val treeUri = call.argument<String>("treeUri")
                        if (treeUri.isNullOrBlank()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val tree = DocumentFile.fromTreeUri(this, Uri.parse(treeUri))
                                if (tree == null) {
                                    runOnUiThread { result.success(false) }
                                    return@Thread
                                }

                                val tempName = "cts_test_${System.currentTimeMillis()}.tmp"
                                val tempFile = tree.createFile("application/octet-stream", tempName)
                                if (tempFile == null) {
                                    runOnUiThread { result.success(false) }
                                    return@Thread
                                }

                                contentResolver.openOutputStream(tempFile.uri)?.use { output ->
                                    output.write(byteArrayOf(0))
                                } ?: run {
                                    tempFile.delete()
                                    runOnUiThread { result.success(false) }
                                    return@Thread
                                }

                                val deleted = tempFile.delete()
                                runOnUiThread { result.success(deleted) }
                            } catch (e: Exception) {
                                runOnUiThread { result.success(false) }
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

        // Foreground service control channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "convert_the_spire/foreground")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForegroundService" -> {
                        try {
                            val intent = ForegroundDownloadService.createStartIntent(this)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                ContextCompat.startForegroundService(this, intent)
                            } else {
                                startService(intent)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("START_FAILED", e.message, null)
                        }
                    }
                    "stopForegroundService" -> {
                        try {
                            val intent = ForegroundDownloadService.createStopIntent(this)
                            startService(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("STOP_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
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
        // API 29+ (Q) use MediaStore Downloads (scoped storage)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
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

        // Fallback for API < 29: write directly to the public Downloads folder.
        try {
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            val baseDir = if (subdir.isNullOrBlank()) {
                File(downloadsDir, "ConvertTheSpireReborn")
            } else {
                File(downloadsDir, "ConvertTheSpireReborn/$subdir")
            }
            if (!baseDir.exists()) baseDir.mkdirs()
            val destFile = File(baseDir, displayName)
            if (destFile.exists()) destFile.delete()

            FileInputStream(File(sourcePath)).use { input ->
                destFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }

            // Try to notify media scanner so the file appears in Downloads/Media
            try {
                MediaScannerConnection.scanFile(this, arrayOf(destFile.absolutePath), arrayOf(mimeType), null)
            } catch (_: Exception) {
            }

            return Uri.fromFile(destFile)
        } catch (e: Exception) {
            return null
        }
    }
}
