package com.kodmoz.screen

import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.io.IOException
import java.net.ConnectException
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Mac sunucusuna TCP bağlantısı. Tek bir IO iş parçacığı okuma/yazma
 * yapar; video kareleri doğrudan çözücüye iletilir.
 */
class StreamClient(
    private val host: String,
    private val port: Int,
    private val code: String,
    private val deviceName: String,
) {
    var onHello: ((ServerHello) -> Unit)? = null
    var onVideo: ((ByteArray, Boolean) -> Unit)? = null
    var onStats: ((Double, Double) -> Unit)? = null
    var onRtt: ((Long) -> Unit)? = null
    var onClosed: ((String, String?) -> Unit)? = null

    private val io = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "kodmoz-net").apply { isDaemon = true }
    }
    private val writeLock = Any()
    private val notified = AtomicBoolean(false)

    @Volatile private var running = false
    @Volatile private var socket: Socket? = null
    @Volatile private var output: DataOutputStream? = null
    @Volatile private var pingThread: Thread? = null
    private var writerThread: Thread? = null
    private val outbox = LinkedBlockingQueue<ByteArray>(256)

    fun connect() {
        io.execute {
            try {
                val socket = Socket()
                socket.tcpNoDelay = true
                socket.keepAlive = true
                socket.soTimeout = 8_000
                socket.connect(InetSocketAddress(host, port), 8_000)
                this.socket = socket
                val output = DataOutputStream(BufferedOutputStream(socket.getOutputStream()))
                val input = DataInputStream(BufferedInputStream(socket.getInputStream()))
                this.output = output
                running = true

                output.write(Wire.handshake(deviceName, code, 0, 0, 60))
                output.flush()

                // Önce 8 bayt: ya "KODMOZSC" ya da bir hata çerçevesi.
                val first = ByteArray(8)
                input.readFully(first)
                if (!first.contentEquals(Wire.MAGIC)) {
                    val type = first[0].toInt() and 0xff
                    val length = ByteBuffer.wrap(first, 4, 4)
                        .order(ByteOrder.BIG_ENDIAN).int
                    if (type == Wire.TYPE_ERROR && length in 0..65_536) {
                        val payload = ByteArray(length)
                        input.readFully(payload)
                        val failure = Wire.parseError(String(payload, Charsets.UTF_8))
                        closeQuietly()
                        notifyClosed(
                            failure?.message ?: "Bağlantı reddedildi.",
                            failure?.code
                        )
                        return@execute
                    }
                    closeQuietly()
                    notifyClosed("Sunucu yanıtı geçersiz.", null)
                    return@execute
                }

                val rest = ByteArray(8)
                input.readFully(rest)
                val version = rest[0].toInt() and 0xff
                if (version != Wire.VERSION) {
                    closeQuietly()
                    notifyClosed("Protokol sürümü uyumsuz.", "badVersion")
                    return@execute
                }
                val jsonLength = ByteBuffer.wrap(rest, 4, 4)
                    .order(ByteOrder.BIG_ENDIAN).int
                if (jsonLength !in 1..65_536) {
                    closeQuietly()
                    notifyClosed("Sunucu bilgisi okunamadı.", null)
                    return@execute
                }
                val jsonBytes = ByteArray(jsonLength)
                input.readFully(jsonBytes)
                val hello = ServerHello.parse(
                    JSONObject(String(jsonBytes, Charsets.UTF_8))
                )
                if (hello == null) {
                    closeQuietly()
                    notifyClosed("Sunucu bilgisi okunamadı.", null)
                    return@execute
                }

                socket.soTimeout = 0
                startWriter()
                onHello?.invoke(hello)
                startPing()
                readLoop(input)
            } catch (error: Exception) {
                closeQuietly()
                val message = when (error) {
                    is SocketTimeoutException -> "Sunucu yanıt vermedi."
                    is ConnectException -> "Mac'e ulaşılamadı. Aynı ağda mısınız?"
                    is UnknownHostException -> "Adres çözümlenemedi."
                    is EOFException -> "Bağlantı kapandı."
                    else -> error.message ?: "Bağlantı hatası."
                }
                notifyClosed(message, null)
            }
        }
    }

    private fun readLoop(input: DataInputStream) {
        val header = ByteArray(8)
        while (running) {
            input.readFully(header)
            val type = header[0].toInt() and 0xff
            val flags = header[1].toInt() and 0xff
            val length = ByteBuffer.wrap(header, 4, 4)
                .order(ByteOrder.BIG_ENDIAN).int
            if (length < 0 || length > Wire.MAX_PAYLOAD) {
                throw IOException("Geçersiz paket boyutu: $length")
            }
            val payload = if (length > 0) ByteArray(length) else ByteArray(0)
            if (length > 0) input.readFully(payload)

            when (type) {
                Wire.TYPE_VIDEO -> onVideo?.invoke(
                    payload,
                    flags and Wire.FLAG_KEYFRAME != 0
                )

                Wire.TYPE_STATS -> {
                    Wire.parseStats(String(payload, Charsets.UTF_8))?.let {
                        onStats?.invoke(it.fps, it.mbps)
                    }
                }

                Wire.TYPE_PONG -> {
                    if (payload.size >= 8) {
                        val sent = ByteBuffer.wrap(payload)
                            .order(ByteOrder.BIG_ENDIAN).long
                        onRtt?.invoke((System.nanoTime() - sent) / 1_000_000)
                    }
                }

                Wire.TYPE_ERROR -> {
                    val failure = Wire.parseError(String(payload, Charsets.UTF_8))
                    running = false
                    closeQuietly()
                    notifyClosed(
                        failure?.message ?: "Sunucu hatası.",
                        failure?.code
                    )
                }

                Wire.TYPE_BYE -> {
                    running = false
                    closeQuietly()
                    notifyClosed("Sunucu bağlantıyı kapattı.", null)
                }
            }
        }
    }

    /**
     * Girdi olayları UI iş parçacığından gelebilir; Android ana iş
     * parçacığında ağ yazımı yasak olduğu için tek bir yazıcı iş parçacığı
     * kuyruğu boşaltır.
     */
    private fun startWriter() {
        val thread = Thread {
            while (running) {
                val frame = try {
                    outbox.poll(500, TimeUnit.MILLISECONDS)
                } catch (_: InterruptedException) {
                    break
                } ?: continue
                val stream = output ?: continue
                var failed = false
                synchronized(writeLock) {
                    try {
                        stream.write(frame)
                        stream.flush()
                    } catch (_: IOException) {
                        failed = true
                    }
                }
                if (failed) break
            }
        }
        thread.isDaemon = true
        thread.name = "kodmoz-writer"
        thread.start()
        writerThread = thread
    }

    private fun startPing() {
        val thread = Thread {
            while (running) {
                try {
                    Thread.sleep(5_000)
                } catch (_: InterruptedException) {
                    break
                }
                if (!running) break
                val payload = ByteBuffer.allocate(8)
                    .order(ByteOrder.BIG_ENDIAN)
                    .putLong(System.nanoTime())
                    .array()
                send(Wire.frame(Wire.TYPE_PING, payload))
            }
        }
        thread.isDaemon = true
        thread.name = "kodmoz-ping"
        thread.start()
        pingThread = thread
    }

    // MARK: - Gönderme

    fun sendInput(payload: ByteArray) {
        send(Wire.frame(Wire.TYPE_INPUT, payload))
    }

    fun send(frame: ByteArray) {
        if (!running) return
        if (!outbox.offer(frame)) {
            // Kuyruk dolduysa en eski olayı düşür; gecikmeyi büyütmeyelim.
            outbox.poll()
            outbox.offer(frame)
        }
    }

    fun close() {
        running = false
        closeQuietly()
        pingThread?.interrupt()
        pingThread = null
        io.shutdown()
    }

    private fun closeQuietly() {
        running = false
        outbox.clear()
        writerThread?.interrupt()
        writerThread = null
        pingThread?.interrupt()
        pingThread = null
        try {
            socket?.close()
        } catch (_: IOException) {
        }
        socket = null
        output = null
    }

    private fun notifyClosed(message: String, code: String?) {
        if (notified.compareAndSet(false, true)) {
            onClosed?.invoke(message, code)
        }
    }
}
