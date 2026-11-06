package com.kodmoz.screen

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Build
import android.view.Surface
import java.nio.ByteBuffer
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * MediaCodec ile H.264 çözücü. Kareler doğrudan SurfaceView yüzeyine
 * render edilir; Compose tarafında ekstra kopya yoktur.
 */
class VideoDecoder(
    private val surface: Surface,
    private val width: Int,
    private val height: Int,
    private val sps: ByteArray,
    private val pps: ByteArray,
    private val fps: Int,
    private val onError: (String) -> Unit,
) {
    private data class Frame(val data: ByteArray, val keyframe: Boolean)

    private val queue = ArrayBlockingQueue<Frame>(8)
    @Volatile private var running = false
    @Volatile private var sawKeyframe = false
    private var thread: Thread? = null

    fun start() {
        if (running) return
        running = true
        sawKeyframe = false
        thread = Thread({ decodeLoop() }, "kodmoz-decoder").apply {
            isDaemon = true
            start()
        }
    }

    fun submit(data: ByteArray, keyframe: Boolean) {
        if (!running) return
        if (keyframe) {
            sawKeyframe = true
            // Yeni anahtar kare geldiğinde kuyruk tıkanmışsa temizle.
            if (queue.size >= 8) queue.clear()
        }
        if (!sawKeyframe) return

        if (queue.size >= 8) {
            // Baştaki anahtar kareyi asla düşürme; çözücü onunla başlar.
            if (queue.peek()?.keyframe == true && !keyframe) return
            queue.poll()
        }
        queue.offer(Frame(data, keyframe))
    }

    fun stop() {
        if (!running) return
        running = false
        thread?.interrupt()
        try {
            thread?.join(1_500)
        } catch (_: InterruptedException) {
        }
        thread = null
        queue.clear()
    }

    private fun decodeLoop() {
        var codec: MediaCodec? = null
        try {
            val format = MediaFormat.createVideoFormat(
                MediaFormat.MIMETYPE_VIDEO_AVC,
                width,
                height
            )
            format.setByteBuffer("csd-0", ByteBuffer.wrap(sps))
            format.setByteBuffer("csd-1", ByteBuffer.wrap(pps))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                runCatching { format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1) }
            }
            runCatching { format.setInteger(MediaFormat.KEY_PRIORITY, 0) }
            runCatching { format.setInteger(MediaFormat.KEY_MAX_B_FRAMES, 0) }

            codec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            codec.configure(format, surface, null, 0)
            codec.start()

            val info = MediaCodec.BufferInfo()
            val stepUs = 1_000_000L / fps.coerceAtLeast(1)
            var presentationUs = 0L

            while (running) {
                val frame = queue.poll(2, TimeUnit.MILLISECONDS)
                if (frame == null) {
                    drain(codec, info)
                    continue
                }

                var queued = false
                var attempts = 0
                while (running && !queued && attempts < 60) {
                    val index = codec.dequeueInputBuffer(4_000)
                    if (index >= 0) {
                        val buffer = codec.getInputBuffer(index)
                        if (buffer != null) {
                            buffer.clear()
                            buffer.put(frame.data)
                            codec.queueInputBuffer(index, 0, frame.data.size, presentationUs, 0)
                            presentationUs += stepUs
                            queued = true
                        }
                    } else {
                        attempts++
                    }
                    drain(codec, info)
                }
                drain(codec, info)
            }
        } catch (throwable: Throwable) {
            if (running) {
                onError(throwable.message ?: "Video çözücü hatası.")
            }
        } finally {
            running = false
            runCatching { codec?.stop() }
            runCatching { codec?.release() }
        }
    }

    private fun drain(codec: MediaCodec, info: MediaCodec.BufferInfo) {
        while (true) {
            val index = codec.dequeueOutputBuffer(info, 0)
            when {
                index >= 0 -> codec.releaseOutputBuffer(index, true)
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    // Surface çıktısında ek yapılandırma gerekmiyor.
                }
                else -> return
            }
        }
    }
}
