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
import android.graphics.Color
import android.view.KeyEvent
import android.os.SystemClock
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import androidx.core.content.ContextCompat
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.ArrayList

class MainActivity : AudioServiceActivity() {
    private val channelName = "convert_the_spire/saf"
    private val webviewChannel = "com.yourapp/webview_input"
    private val cursorKeysChannel = "com.yourapp/cursor_keys"
    private val pickTreeRequestCode = 5011
    private var pendingResult: MethodChannel.Result? = null
    private var browserWebView: WebView? = null
    private var cursorModeActive = false
    private var keyEventChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 15+ mandatory edge-to-edge support
        // For all supported Android versions, disable window-to-system-window fitting
        // to enable proper edge-to-edge rendering
        WindowCompat.setDecorFitsSystemWindows(window, false)
        
        super.onCreate(savedInstanceState)
        
        // Set window background to transparent for edge-to-edge rendering
        window.decorView.setBackgroundColor(Color.TRANSPARENT)
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
                    "listTree" -> {
                        val treeUri = call.argument<String>("treeUri")
                        if (treeUri.isNullOrBlank()) {
                            result.success(emptyList<Map<String, String>>())
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val items = listTree(treeUri)
                                runOnUiThread { result.success(items) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("LIST_TREE_FAILED", e.localizedMessage, null) }
                            }
                        }.start()
                    }
                    "getPathFromTreeUri" -> {
                        val treeUri = call.argument<String>("treeUri")
                        if (treeUri.isNullOrBlank()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val path = getPathFromTreeUri(treeUri)
                                runOnUiThread { result.success(path) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("GET_PATH_FAILED", e.localizedMessage, null) }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, webviewChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "registerWebView" -> {
                        browserWebView = findWebView(window.decorView.rootView)
                        val url = browserWebView?.url ?: "null"
                        Log.d("CursorBridge", "registerWebView url=$url")
                        result.success(null)
                    }
                    "injectTap" -> {
                        val x = (call.argument<Double>("x") ?: 0.0).toFloat()
                        val y = (call.argument<Double>("y") ?: 0.0).toFloat()
                        var webView = browserWebView

                        // Null-safety fallback: if WebView not yet registered (race condition on slow
                        // devices), attempt re-registration before failing.
                        if (webView == null) {
                            Log.d("CursorBridge", "injectTap: WebView null, attempting re-registration")
                            webView = findWebView(window.decorView.rootView)
                            if (webView != null) {
                                browserWebView = webView
                                Log.d("CursorBridge", "injectTap: Re-registration SUCCESS")
                            } else {
                                Log.e("CursorBridge", "injectTap: Re-registration FAILED")
                                result.error("NO_WEBVIEW", "WebView not found", null)
                                return@setMethodCallHandler
                            }
                        }

                        Log.d("CursorBridge", "injectTap x=$x y=$y url=${webView?.url}")
                        val downTime = SystemClock.uptimeMillis()
                        val down = MotionEvent.obtain(
                            downTime,
                            downTime,
                            MotionEvent.ACTION_DOWN,
                            x,
                            y,
                            0
                        )
                        val up = MotionEvent.obtain(
                            downTime,
                            downTime + 100,
                            MotionEvent.ACTION_UP,
                            x,
                            y,
                            0
                        )

                        webView.post {
                            webView.dispatchTouchEvent(down)
                            webView.dispatchTouchEvent(up)
                            down.recycle()
                            up.recycle()
                            result.success(null)
                        }
                    }
                    "injectScroll" -> {
                        val deltaY = (call.argument<Double>("deltaY") ?: 0.0)
                        val webView2 = browserWebView
                        if (webView2 != null) {
                            Log.d("CursorBridge", "injectScroll deltaY=$deltaY")
                            webView2.post {
                                try {
                                    webView2.evaluateJavascript("window.scrollBy(0, $deltaY)", null)
                                } catch (e: Exception) {
                                    Log.e("CursorBridge", "injectScroll FAILED: $e")
                                }
                            }
                            result.success(null)
                        } else {
                            Log.e("CursorBridge", "injectScroll: WebView not registered")
                            result.error("NO_WEBVIEW", "WebView not registered", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        keyEventChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, cursorKeysChannel)
        keyEventChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setCursorActive" -> {
                    cursorModeActive = call.argument<Boolean>("active") ?: false
                    val webView = browserWebView
                    if (webView != null) {
                        webView.post {
                            if (cursorModeActive) {
                                webView.isFocusable = false
                                webView.isFocusableInTouchMode = false
                                webView.clearFocus()
                                Log.d("CursorBridge", "WebView focus disabled for cursor mode")
                            } else {
                                webView.isFocusable = true
                                webView.isFocusableInTouchMode = true
                                Log.d("CursorBridge", "WebView focus restored")
                            }
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (cursorModeActive && isCursorKeyEvent(event)) {
            val action = when (event.action) {
                KeyEvent.ACTION_DOWN -> "down"
                KeyEvent.ACTION_UP -> "up"
                else -> return true
            }

            keyEventChannel?.invokeMethod(
                "onDpadKey",
                mapOf(
                    "keyCode" to event.keyCode,
                    "action" to action,
                    "repeatCount" to event.repeatCount,
                ),
            )
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    private fun isCursorKeyEvent(event: KeyEvent): Boolean {
        return when (event.keyCode) {
            KeyEvent.KEYCODE_DPAD_UP,
            KeyEvent.KEYCODE_DPAD_DOWN,
            KeyEvent.KEYCODE_DPAD_LEFT,
            KeyEvent.KEYCODE_DPAD_RIGHT,
            KeyEvent.KEYCODE_DPAD_CENTER,
            KeyEvent.KEYCODE_ENTER,
            KeyEvent.KEYCODE_NUMPAD_ENTER -> true
            else -> false
        }
    }

    private fun findWebView(view: View): WebView? {
        if (view is WebView) {
            Log.d("CursorBridge", "Found WebView: ${view.javaClass.simpleName}")
            return view
        }
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                val found = findWebView(view.getChildAt(index))
                if (found != null) return found
            }
        }
        return null
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

    private fun listTree(treeUriString: String): List<Map<String, String>> {
        val treeUri = Uri.parse(treeUriString)
        val root = DocumentFile.fromTreeUri(this, treeUri) ?: return emptyList()
        val items = ArrayList<Map<String, String>>()

        fun walk(document: DocumentFile) {
            for (child in document.listFiles()) {
                if (!child.exists()) continue
                if (child.isDirectory) {
                    walk(child)
                    continue
                }
                if (!child.isFile) continue
                items.add(
                    mapOf(
                        "uri" to child.uri.toString(),
                        "name" to (child.name ?: child.uri.lastPathSegment ?: ""),
                        "mimeType" to (child.type ?: ""),
                        "size" to child.length().toString(),
                        "lastModified" to child.lastModified().toString(),
                    )
                )
            }
        }

        walk(root)
        return items
    }

    private fun copyContentUriToTemp(uriString: String): String? {
        val srcUri = Uri.parse(uriString)
        val tempFile = File.createTempFile("saf_", null, cacheDir)
        contentResolver.openInputStream(srcUri)?.use { input ->
            FileOutputStream(tempFile).use { output -> input.copyTo(output) }
        } ?: return null
        return tempFile.absolutePath
    }

    private fun getPathFromTreeUri(treeUriString: String): String? {
        return try {
            val treeUri = Uri.parse(treeUriString)
            val documentFile = DocumentFile.fromTreeUri(this, treeUri) ?: return null
            // Try to get the actual file path if this is a real file system directory
            // This works for USB drives and external storage mounted as directories
            val path = documentFile.uri.path
            if (path != null && path.startsWith("/storage/")) {
                // This is a real filesystem path, not a content:// provider path
                path
            } else {
                // For SAF URIs without direct filesystem paths, we return the tree URI itself
                // The Dart code will need to handle this as a special case
                treeUriString
            }
        } catch (e: Exception) {
            null
        }
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
