package com.kodmoz.screen

import android.util.Base64
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Mac tarafındaki Protocol.swift ile birebir aynı tel formatı. */
object Wire {
    /** "KODMOZSC" */
    val MAGIC = byteArrayOf(
        0x4B, 0x4F, 0x44, 0x4D, 0x4F, 0x5A, 0x53, 0x43
    )

    const val VERSION = 1
    const val TYPE_VIDEO = 1
    const val TYPE_INPUT = 2
    const val TYPE_PING = 3
    const val TYPE_PONG = 4
    const val TYPE_STATS = 5
    const val TYPE_ERROR = 6
    const val TYPE_BYE = 7

    const val FLAG_KEYFRAME = 1
    const val MAX_PAYLOAD = 8 * 1024 * 1024

    fun handshake(device: String, code: String, width: Int, height: Int, fps: Int): ByteArray {
        val json = JSONObject()
            .put("protocol", VERSION)
            .put("device", device)
            .put("code", code)
            .put("width", width)
            .put("height", height)
            .put("fps", fps)
            .toString()
            .toByteArray(Charsets.UTF_8)

        val buffer = ByteBuffer.allocate(16 + json.size).order(ByteOrder.BIG_ENDIAN)
        buffer.put(MAGIC)
        buffer.put(VERSION.toByte())
        buffer.put(byteArrayOf(0, 0, 0))
        buffer.putInt(json.size)
        buffer.put(json)
        return buffer.array()
    }

    fun frame(type: Int, payload: ByteArray): ByteArray {
        val buffer = ByteBuffer.allocate(8 + payload.size).order(ByteOrder.BIG_ENDIAN)
        buffer.put(type.toByte())
        buffer.put(0)
        buffer.putShort(0)
        buffer.putInt(payload.size)
        buffer.put(payload)
        return buffer.array()
    }

    // MARK: - Girdi olayları

    fun inputMove(x: Float, y: Float): ByteArray {
        val buffer = ByteBuffer.allocate(5).order(ByteOrder.BIG_ENDIAN)
        buffer.put(0)
        buffer.putShort((x.coerceIn(0f, 1f) * 65535f).toInt().toShort())
        buffer.putShort((y.coerceIn(0f, 1f) * 65535f).toInt().toShort())
        return buffer.array()
    }

    fun inputButton(
        x: Float,
        y: Float,
        button: Int,
        down: Boolean,
        clickCount: Int
    ): ByteArray {
        val buffer = ByteBuffer.allocate(9).order(ByteOrder.BIG_ENDIAN)
        buffer.put(1)
        buffer.putShort((x.coerceIn(0f, 1f) * 65535f).toInt().toShort())
        buffer.putShort((y.coerceIn(0f, 1f) * 65535f).toInt().toShort())
        buffer.put(button.toByte())
        buffer.put(if (down) 1 else 0)
        buffer.put(clickCount.coerceIn(1, 3).toByte())
        buffer.put(0)
        return buffer.array()
    }

    fun inputScroll(dx: Float, dy: Float): ByteArray {
        val buffer = ByteBuffer.allocate(5).order(ByteOrder.BIG_ENDIAN)
        buffer.put(2)
        buffer.putShort(dx.toInt().coerceIn(-32768, 32767).toShort())
        buffer.putShort(dy.toInt().coerceIn(-32768, 32767).toShort())
        return buffer.array()
    }

    fun inputKey(code: Int, down: Boolean, meta: Int): ByteArray {
        val buffer = ByteBuffer.allocate(5).order(ByteOrder.BIG_ENDIAN)
        buffer.put(3)
        buffer.putShort(code.toShort())
        buffer.put(if (down) 1 else 0)
        buffer.put(meta.toByte())
        return buffer.array()
    }

    fun inputText(text: String): ByteArray {
        val bytes = text.toByteArray(Charsets.UTF_8)
        val buffer = ByteBuffer.allocate(1 + bytes.size).order(ByteOrder.BIG_ENDIAN)
        buffer.put(4)
        buffer.put(bytes)
        return buffer.array()
    }

    // MARK: - Sunucu mesajları

    fun parseError(json: String): ServerFailure? = runCatching {
        val objectJson = JSONObject(json)
        ServerFailure(
            objectJson.optString("message", "Sunucu hatası"),
            objectJson.optString("code", "")
        )
    }.getOrNull()

    fun parseStats(json: String): StatsPayload? = runCatching {
        val objectJson = JSONObject(json)
        StatsPayload(objectJson.optDouble("fps", 0.0), objectJson.optDouble("mbps", 0.0))
    }.getOrNull()
}

data class ServerFailure(val message: String, val code: String)
data class StatsPayload(val fps: Double, val mbps: Double)

data class ServerHello(
    val width: Int,
    val height: Int,
    val fps: Int,
    val bitrate: Int,
    val codec: String,
    val sps: ByteArray,
    val pps: ByteArray,
    val display: String,
    val scale: Int,
) {
    companion object {
        fun parse(json: JSONObject): ServerHello? {
            if (!json.optBoolean("ok", true)) return null
            val sps = runCatching {
                Base64.decode(json.getString("sps"), Base64.DEFAULT)
            }.getOrNull() ?: return null
            val pps = runCatching {
                Base64.decode(json.getString("pps"), Base64.DEFAULT)
            }.getOrNull() ?: return null
            return ServerHello(
                width = json.optInt("width", 1280),
                height = json.optInt("height", 800),
                fps = json.optInt("fps", 60),
                bitrate = json.optInt("bitrate", 12_000_000),
                codec = json.optString("codec", "avc"),
                sps = sps,
                pps = pps,
                display = json.optString("display", "Kodmoz Screen"),
                scale = json.optInt("scale", 2),
            )
        }
    }
}
