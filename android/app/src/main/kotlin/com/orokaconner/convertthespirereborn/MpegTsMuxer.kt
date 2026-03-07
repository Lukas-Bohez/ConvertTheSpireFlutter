package com.orokaconner.convertthespirereborn

import java.io.ByteArrayOutputStream

/**
 * Minimal MPEG-TS muxer for a single H.264 video stream and optional AAC audio.
 * Produces standard 188-byte transport stream packets.
 */
class MpegTsMuxer {
    companion object {
        const val TS_SIZE = 188
        const val SYNC: Byte = 0x47
        const val PAT_PID = 0
        const val PMT_PID = 0x1000
        const val VIDEO_PID = 0x100
        const val AUDIO_PID = 0x101
    }

    private var videoCc = 0
    private var audioCc = 0
    private var patCc = 0
    private var pmtCc = 0
    var hasAudio = false

    /** Generate PAT + PMT tables. Call before each keyframe. */
    fun tables(): List<ByteArray> = listOf(pat(), pmt())

    /** Wrap H.264 access unit into TS packets with PES header. */
    fun video(data: ByteArray, ptsUs: Long, keyFrame: Boolean): List<ByteArray> {
        val pts = ptsUs * 9 / 100 // microseconds → 90 kHz clock
        return packetize(VIDEO_PID, pes(0xE0, data, pts), keyFrame, pts, true)
    }

    /** Wrap AAC frame (with ADTS header) into TS packets with PES header. */
    fun audio(data: ByteArray, ptsUs: Long): List<ByteArray> {
        val pts = ptsUs * 9 / 100
        return packetize(AUDIO_PID, pes(0xC0, data, pts), false, 0, false)
    }

    // ── PAT ────────────────────────────────────────────────────────────────

    private fun pat(): ByteArray {
        val sec = byteArrayOf(
            0x00,                                              // table_id
            0xB0.toByte(), 0x0D,                               // section_syntax + length=13
            0x00, 0x01,                                        // transport_stream_id
            0xC1.toByte(),                                     // version=0, current_next=1
            0x00, 0x00,                                        // section/last section
            0x00, 0x01,                                        // program_number=1
            ((PMT_PID shr 8) or 0xE0).toByte(),
            (PMT_PID and 0xFF).toByte()
        )
        return tablePacket(PAT_PID, sec, true)
    }

    // ── PMT ────────────────────────────────────────────────────────────────

    private fun pmt(): ByteArray {
        val streams = ByteArrayOutputStream()
        // Video: H.264 (stream type 0x1B)
        streams.write(0x1B)
        streams.write((VIDEO_PID shr 8) or 0xE0); streams.write(VIDEO_PID and 0xFF)
        streams.write(0xF0); streams.write(0x00) // ES_info_length=0
        if (hasAudio) {
            // Audio: AAC (stream type 0x0F)
            streams.write(0x0F)
            streams.write((AUDIO_PID shr 8) or 0xE0); streams.write(AUDIO_PID and 0xFF)
            streams.write(0xF0); streams.write(0x00)
        }
        val sd = streams.toByteArray()

        val bos = ByteArrayOutputStream()
        bos.write(0x02) // table_id
        val sLen = 9 + sd.size + 4 // fixed(9) + streams + CRC(4)
        bos.write((sLen shr 8) or 0xB0); bos.write(sLen and 0xFF)
        bos.write(0x00); bos.write(0x01)              // program_number=1
        bos.write(0xC1.toInt())                        // version=0, current_next=1
        bos.write(0x00); bos.write(0x00)               // section/last
        bos.write((VIDEO_PID shr 8) or 0xE0)           // PCR PID
        bos.write(VIDEO_PID and 0xFF)
        bos.write(0xF0); bos.write(0x00)               // program_info_length=0
        bos.write(sd)
        return tablePacket(PMT_PID, bos.toByteArray(), false)
    }

    private fun tablePacket(pid: Int, section: ByteArray, isPat: Boolean): ByteArray {
        val crc = crc32(section)
        // pointer_field(1) + section + CRC
        val payload = byteArrayOf(0x00) + section + crc
        val pkt = ByteArray(TS_SIZE) { 0xFF.toByte() }
        pkt[0] = SYNC
        pkt[1] = (0x40 or ((pid shr 8) and 0x1F)).toByte()
        pkt[2] = (pid and 0xFF).toByte()
        val cc = if (isPat) patCc++ and 0x0F else pmtCc++ and 0x0F
        pkt[3] = (0x10 or cc).toByte()
        System.arraycopy(payload, 0, pkt, 4, payload.size)
        return pkt
    }

    // ── PES ────────────────────────────────────────────────────────────────

    private fun pes(streamId: Int, data: ByteArray, pts90k: Long): ByteArray {
        val bos = ByteArrayOutputStream(data.size + 14)
        bos.write(0x00); bos.write(0x00); bos.write(0x01)
        bos.write(streamId)
        // PES length: 0 = unbounded for video; bounded for audio
        val pLen = if (streamId >= 0xE0) 0 else minOf(data.size + 8, 65535)
        bos.write((pLen shr 8) and 0xFF); bos.write(pLen and 0xFF)
        bos.write(0x80) // marker
        bos.write(0x80) // PTS flag
        bos.write(0x05) // PES header data length
        // PTS (5 bytes): '0010' | PTS[32:30] | '1' | PTS[29:15] | '1' | PTS[14:0] | '1'
        bos.write(0x21 or (((pts90k shr 29) and 0x0E).toInt()))
        bos.write(((pts90k shr 22) and 0xFF).toInt())
        bos.write(0x01 or (((pts90k shr 14) and 0xFE).toInt()))
        bos.write(((pts90k shr 7) and 0xFF).toInt())
        bos.write(0x01 or (((pts90k shl 1) and 0xFE).toInt()))
        bos.write(data)
        return bos.toByteArray()
    }

    // ── TS packetizer ──────────────────────────────────────────────────────

    private fun packetize(
        pid: Int, pesData: ByteArray, withPCR: Boolean, pcr90k: Long, isVideo: Boolean
    ): List<ByteArray> {
        val result = mutableListOf<ByteArray>()
        var off = 0
        var first = true

        while (off < pesData.size) {
            val pkt = ByteArray(TS_SIZE) { 0xFF.toByte() }
            val remaining = pesData.size - off
            val cc = if (isVideo) videoCc++ and 0x0F else audioCc++ and 0x0F

            val needPcr = first && withPCR
            // Minimum adaptation field content size (excluding the length byte)
            val minAfContent = if (needPcr) 7 else 0 // flags(1) + PCR(6)
            // Available payload when AF is present: 188 - 4(header) - 1(af_length) - afContent
            val maxPayloadWithAf = TS_SIZE - 4 - 1 - minAfContent
            // Available payload without AF: 184
            val maxPayloadNoAf = TS_SIZE - 4

            val payloadSize: Int
            val hasAf: Boolean

            if (needPcr) {
                // Must have AF for PCR
                payloadSize = minOf(remaining, maxPayloadWithAf)
                hasAf = true
            } else if (remaining >= maxPayloadNoAf) {
                // Fits without AF or takes full packet
                payloadSize = maxPayloadNoAf
                hasAf = false
            } else {
                // Needs stuffing → AF required
                payloadSize = remaining
                hasAf = true
            }

            var p = 0
            pkt[p++] = SYNC
            pkt[p++] = (((if (first) 0x40 else 0) or ((pid shr 8) and 0x1F))).toByte()
            pkt[p++] = (pid and 0xFF).toByte()
            pkt[p++] = ((if (hasAf) 0x30 else 0x10) or cc).toByte()

            if (hasAf) {
                // Total AF bytes = everything between header and payload
                val afTotal = TS_SIZE - 4 - payloadSize
                val afLen = afTotal - 1 // adaptation_field_length value
                pkt[p++] = afLen.toByte()

                if (afLen > 0) {
                    if (needPcr) {
                        pkt[p++] = 0x10 // PCR flag
                        pkt[p++] = ((pcr90k shr 25) and 0xFF).toByte()
                        pkt[p++] = ((pcr90k shr 17) and 0xFF).toByte()
                        pkt[p++] = ((pcr90k shr 9) and 0xFF).toByte()
                        pkt[p++] = ((pcr90k shr 1) and 0xFF).toByte()
                        pkt[p++] = (((pcr90k and 1) shl 7) or 0x7E).toByte()
                        pkt[p] = 0x00
                    } else {
                        pkt[p] = 0x00 // flags: nothing
                    }
                }
                // Remaining AF bytes are already 0xFF (stuffing) from array init
            }

            // Payload goes at the end of the packet
            System.arraycopy(pesData, off, pkt, TS_SIZE - payloadSize, payloadSize)
            off += payloadSize
            first = false
            result.add(pkt)
        }
        return result
    }

    // ── CRC-32/MPEG-2 ─────────────────────────────────────────────────────

    private fun crc32(data: ByteArray): ByteArray {
        var crc = 0xFFFFFFFFL
        for (b in data) {
            var byte = (b.toLong() and 0xFF) shl 24
            for (bit in 0 until 8) {
                crc = if ((crc xor byte) and 0x80000000L != 0L) {
                    ((crc shl 1) xor 0x04C11DB7L) and 0xFFFFFFFFL
                } else {
                    (crc shl 1) and 0xFFFFFFFFL
                }
                byte = (byte shl 1) and 0xFFFFFFFFL
            }
        }
        return byteArrayOf(
            ((crc shr 24) and 0xFF).toByte(),
            ((crc shr 16) and 0xFF).toByte(),
            ((crc shr 8) and 0xFF).toByte(),
            (crc and 0xFF).toByte()
        )
    }
}
