package com.orokaconner.convertthespirereborn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import java.io.OutputStream
import java.net.ServerSocket

class ScreenCaptureService : Service() {

    companion object {
        const val TAG = "ScreenCast"
        const val NOTIFICATION_ID = 9001
        const val CHANNEL_ID = "screencast_channel"
        const val ACTION_START = "start"
        const val ACTION_STOP = "stop"

        @Volatile var resultCode: Int = 0
        @Volatile var resultData: Intent? = null
        @Volatile var streamPort: Int = 0
        @Volatile var isRunning: Boolean = false
        @Volatile var lastError: String? = null
        @Volatile var audioGranted: Boolean = false
    }

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var videoEncoder: MediaCodec? = null
    private var audioEncoder: MediaCodec? = null
    private var audioRecord: AudioRecord? = null
    private var serverSocket: ServerSocket? = null
    private val muxer = MpegTsMuxer()
    private val clients = mutableListOf<OutputStream>()
    @Volatile private var running = false
    private var spsAndPps: ByteArray? = null
    @Volatile private var ptsOffset = -1L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startCapture(intent)
            ACTION_STOP -> stopCapture()
        }
        return START_NOT_STICKY
    }

    private fun startCapture(intent: Intent) {
        try {
            val width = intent.getIntExtra("width", 1920)
            val height = intent.getIntExtra("height", 1080)
            val fps = intent.getIntExtra("fps", 30)
            val dpi = resources.displayMetrics.densityDpi
            lastError = null

            // Must start foreground BEFORE creating MediaProjection (Android 14 requirement)
            startForeground(NOTIFICATION_ID, buildNotification())

            val projMgr = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            mediaProjection = projMgr.getMediaProjection(resultCode, resultData!!)

            // HTTP server
            serverSocket = ServerSocket(0)
            streamPort = serverSocket!!.localPort
            running = true
            isRunning = true
            Thread(::acceptClients, "screencast-http").start()

            // Video encoder (H.264)
            val vFmt = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
                setInteger(MediaFormat.KEY_BIT_RATE, 4_000_000)
                setInteger(MediaFormat.KEY_FRAME_RATE, fps)
                setFloat(MediaFormat.KEY_I_FRAME_INTERVAL, 2f)
                setInteger(MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            }
            videoEncoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC).apply {
                configure(vFmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            }
            val surface = videoEncoder!!.createInputSurface()
            videoEncoder!!.start()

            // VirtualDisplay
            virtualDisplay = mediaProjection!!.createVirtualDisplay(
                "ScreenCast", width, height, dpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                surface, null, null
            )
            Thread(::processVideoOutput, "screencast-video").start()

            // Audio capture (Android 10+ with permission)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && audioGranted) {
                setupAudioCapture()
            }

        } catch (e: Exception) {
            Log.e(TAG, "startCapture failed", e)
            lastError = e.message
            isRunning = false
            running = false
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    @Suppress("MissingPermission") // Permission checked in Activity before calling
    private fun setupAudioCapture() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        try {
            val audioFmt = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(44100)
                .setChannelMask(AudioFormat.CHANNEL_IN_STEREO)
                .build()

            val captureConfig = AudioPlaybackCaptureConfiguration.Builder(mediaProjection!!)
                .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                .addMatchingUsage(AudioAttributes.USAGE_GAME)
                .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                .build()

            audioRecord = AudioRecord.Builder()
                .setAudioPlaybackCaptureConfig(captureConfig)
                .setAudioFormat(audioFmt)
                .build()

            val aFmt = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, 44100, 2).apply {
                setInteger(MediaFormat.KEY_BIT_RATE, 128_000)
                setInteger(MediaFormat.KEY_AAC_PROFILE,
                    MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            }
            audioEncoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC).apply {
                configure(aFmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                start()
            }
            audioRecord!!.startRecording()
            muxer.hasAudio = true

            Thread(::feedAudioEncoder, "screencast-audio-in").start()
            Thread(::processAudioOutput, "screencast-audio-out").start()
            Log.i(TAG, "Audio capture started")
        } catch (e: Exception) {
            Log.w(TAG, "Audio capture unavailable, video only: ${e.message}")
            audioRecord?.release(); audioRecord = null
            audioEncoder?.release(); audioEncoder = null
        }
    }

    // ── Video encoder output ───────────────────────────────────────────────

    private fun processVideoOutput() {
        val info = MediaCodec.BufferInfo()
        while (running) {
            val idx = videoEncoder?.dequeueOutputBuffer(info, 10_000) ?: break
            if (idx < 0) continue
            val buf = videoEncoder!!.getOutputBuffer(idx) ?: continue
            val data = ByteArray(info.size); buf.get(data)

            if ((info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
                spsAndPps = data.copyOf()
                videoEncoder!!.releaseOutputBuffer(idx, false)
                continue
            }

            var pts = info.presentationTimeUs
            synchronized(this) { if (ptsOffset < 0) ptsOffset = pts }
            pts -= ptsOffset

            val isKey = (info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME) != 0
            val frameData = if (isKey && spsAndPps != null) spsAndPps!! + data else data

            if (isKey) broadcast(muxer.tables())
            broadcast(muxer.video(frameData, pts, isKey))
            videoEncoder!!.releaseOutputBuffer(idx, false)
        }
    }

    // ── Audio encoder I/O ──────────────────────────────────────────────────

    private fun feedAudioEncoder() {
        val buf = ByteArray(4096)
        while (running) {
            val read = audioRecord?.read(buf, 0, buf.size) ?: break
            if (read <= 0) continue
            val idx = audioEncoder?.dequeueInputBuffer(10_000) ?: break
            if (idx < 0) continue
            val inBuf = audioEncoder!!.getInputBuffer(idx) ?: continue
            inBuf.clear(); inBuf.put(buf, 0, read)
            audioEncoder!!.queueInputBuffer(idx, 0, read, System.nanoTime() / 1000, 0)
        }
    }

    private fun processAudioOutput() {
        val info = MediaCodec.BufferInfo()
        while (running) {
            val idx = audioEncoder?.dequeueOutputBuffer(info, 10_000) ?: break
            if (idx < 0) continue
            if ((info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
                audioEncoder!!.releaseOutputBuffer(idx, false)
                continue
            }
            val buf = audioEncoder!!.getOutputBuffer(idx) ?: continue
            val data = ByteArray(info.size); buf.get(data)

            var pts = info.presentationTimeUs
            synchronized(this) { if (ptsOffset < 0) ptsOffset = pts }
            pts -= ptsOffset

            val adts = adtsHeader(data, 44100, 2)
            broadcast(muxer.audio(adts, pts))
            audioEncoder!!.releaseOutputBuffer(idx, false)
        }
    }

    /** Wrap raw AAC frame with a 7-byte ADTS header. */
    private fun adtsHeader(aac: ByteArray, sampleRate: Int, channels: Int): ByteArray {
        val frameLen = 7 + aac.size
        val freqIdx = when (sampleRate) {
            96000 -> 0; 88200 -> 1; 64000 -> 2; 48000 -> 3
            44100 -> 4; 32000 -> 5; 24000 -> 6; 22050 -> 7
            16000 -> 8; 12000 -> 9; 11025 -> 10; 8000 -> 11
            else -> 4
        }
        val profile = 1 // AAC-LC
        val h = ByteArray(7)
        h[0] = 0xFF.toByte()
        h[1] = 0xF1.toByte() // sync + MPEG-4 + no CRC
        h[2] = ((profile shl 6) or (freqIdx shl 2) or (channels shr 2)).toByte()
        h[3] = (((channels and 3) shl 6) or ((frameLen shr 11) and 3)).toByte()
        h[4] = ((frameLen shr 3) and 0xFF).toByte()
        h[5] = (((frameLen and 7) shl 5) or 0x1F).toByte()
        h[6] = 0xFC.toByte()
        return h + aac
    }

    // ── HTTP server ────────────────────────────────────────────────────────

    private fun acceptClients() {
        while (running) {
            try {
                val client = serverSocket?.accept() ?: break
                client.soTimeout = 5000
                Thread {
                    try {
                        val reader = client.getInputStream().bufferedReader()
                        val requestLine = reader.readLine() ?: ""
                        // Consume remaining headers
                        var line = reader.readLine()
                        while (!line.isNullOrBlank()) line = reader.readLine()

                        val output = client.getOutputStream()
                        if (requestLine.startsWith("HEAD")) {
                            output.write(("HTTP/1.1 200 OK\r\nContent-Type: video/mp2t\r\n" +
                                "transferMode.dlna.org: Streaming\r\n\r\n").toByteArray())
                            output.flush(); client.close()
                            return@Thread
                        }
                        val headers = "HTTP/1.1 200 OK\r\n" +
                            "Content-Type: video/mp2t\r\n" +
                            "Connection: keep-alive\r\n" +
                            "Cache-Control: no-cache\r\n" +
                            "transferMode.dlna.org: Streaming\r\n\r\n"
                        output.write(headers.toByteArray())
                        output.flush()
                        // Reset socket timeout for streaming (infinite)
                        client.soTimeout = 0
                        synchronized(clients) { clients.add(output) }
                    } catch (e: Exception) {
                        try { client.close() } catch (_: Exception) {}
                    }
                }.start()
            } catch (e: Exception) {
                if (running) Log.e(TAG, "Accept error", e)
            }
        }
    }

    private fun broadcast(packets: List<ByteArray>) {
        synchronized(clients) {
            val iter = clients.iterator()
            while (iter.hasNext()) {
                val out = iter.next()
                try {
                    for (pkt in packets) out.write(pkt)
                    out.flush()
                } catch (_: Exception) { iter.remove() }
            }
        }
    }

    // ── Lifecycle ──────────────────────────────────────────────────────────

    private fun stopCapture() {
        running = false
        isRunning = false

        audioRecord?.stop(); audioRecord?.release(); audioRecord = null
        try { audioEncoder?.stop() } catch (_: Exception) {}
        audioEncoder?.release(); audioEncoder = null
        try { videoEncoder?.stop() } catch (_: Exception) {}
        videoEncoder?.release(); videoEncoder = null
        virtualDisplay?.release(); virtualDisplay = null
        mediaProjection?.stop(); mediaProjection = null

        synchronized(clients) {
            for (c in clients) try { c.close() } catch (_: Exception) {}
            clients.clear()
        }
        try { serverSocket?.close() } catch (_: Exception) {}
        serverSocket = null
        ptsOffset = -1L
        spsAndPps = null

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        if (running) stopCapture()
        super.onDestroy()
    }

    // ── Notification ───────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL_ID, "Screen Cast", NotificationManager.IMPORTANCE_LOW)
                .apply { description = "Screen casting is active" }
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }

    private fun buildNotification(): Notification {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }.setContentTitle("Screen Cast")
            .setContentText("Streaming to TV…")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setOngoing(true)
            .build()
    }
}
