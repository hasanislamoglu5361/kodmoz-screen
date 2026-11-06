package com.kodmoz.screen

import android.app.Application
import android.os.Build
import android.view.Surface
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlin.math.min

class SessionViewModel(
    application: Application,
    val target: Target,
) : AndroidViewModel(application) {

    data class Target(
        val host: String,
        val port: Int,
        val code: String,
        val name: String,
        val id: String = java.util.UUID.randomUUID().toString(),
    )

    enum class Phase { Connecting, Streaming, Reconnecting, Failed }

    data class UiState(
        val phase: Phase = Phase.Connecting,
        val fps: Double = 0.0,
        val mbps: Double = 0.0,
        val rttMs: Long = -1,
        val width: Int = 0,
        val height: Int = 0,
        val displayName: String = "",
        val error: String? = null,
        val attempt: Int = 0,
    )

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    private var client: StreamClient? = null
    private var decoder: VideoDecoder? = null
    private var decoderSurface: Surface? = null
    private var hello: ServerHello? = null

    @Volatile private var surface: Surface? = null
    private var retryJob: Job? = null
    private var closed = false
    private var attempt = 0

    init {
        connect()
    }

    private fun connect() {
        if (closed) return
        retryJob?.cancel()
        client?.close()
        hello = null
        decoder?.stop()
        decoder = null

        _state.update {
            it.copy(
                phase = if (attempt == 0) Phase.Connecting else Phase.Reconnecting,
                error = null,
                attempt = attempt,
            )
        }

        val newClient = StreamClient(
            host = target.host,
            port = target.port,
            code = target.code,
            deviceName = "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
        )
        newClient.onHello = { serverHello ->
            hello = serverHello
            attempt = 0
            _state.update {
                it.copy(
                    phase = Phase.Streaming,
                    width = serverHello.width,
                    height = serverHello.height,
                    displayName = serverHello.display,
                    error = null,
                    attempt = 0,
                )
            }
            maybeCreateDecoder()
        }
        newClient.onVideo = { data, keyframe ->
            decoder?.submit(data, keyframe)
        }
        newClient.onStats = { fps, mbps ->
            _state.update { it.copy(fps = fps, mbps = mbps) }
        }
        newClient.onRtt = { rtt ->
            _state.update { it.copy(rttMs = rtt) }
        }
        newClient.onClosed = { message, code ->
            onDisconnected(message, code)
        }
        client = newClient
        newClient.connect()
    }

    fun attachSurface(newSurface: Surface) {
        if (surface === newSurface && decoder != null) return
        decoder?.stop()
        decoder = null
        decoderSurface = null
        surface = newSurface
        maybeCreateDecoder()
    }

    fun detachSurface() {
        decoder?.stop()
        decoder = null
        decoderSurface = null
        surface = null
    }

    private fun maybeCreateDecoder() {
        val currentSurface = surface ?: return
        val serverHello = hello ?: return
        if (decoder != null && decoderSurface === currentSurface) return
        decoder?.stop()
        decoder = null

        val newDecoder = VideoDecoder(
            surface = currentSurface,
            width = serverHello.width,
            height = serverHello.height,
            sps = serverHello.sps,
            pps = serverHello.pps,
            fps = serverHello.fps,
        ) { message ->
            onDisconnected("Görüntü çözücü hatası: $message", null)
        }
        newDecoder.start()
        decoder = newDecoder
        decoderSurface = currentSurface
    }

    private fun onDisconnected(message: String, code: String?) {
        if (closed) return
        decoder?.stop()
        decoder = null
        client?.close()
        client = null

        if (code == "badCode") {
            _state.update {
                it.copy(
                    phase = Phase.Failed,
                    error = "Eşleşme kodu hatalı. Mac ekranındaki 4 haneli kodu girin.",
                )
            }
            return
        }

        attempt++
        val delayMs = min(8_000L, 500L * (1L shl min(attempt, 4)))
        _state.update {
            it.copy(
                phase = Phase.Reconnecting,
                error = message,
                attempt = attempt,
            )
        }
        retryJob?.cancel()
        retryJob = viewModelScope.launch {
            delay(delayMs)
            if (!closed) connect()
        }
    }

    fun retry() {
        if (closed) return
        attempt = 0
        retryJob?.cancel()
        connect()
    }

    fun disconnect() {
        closed = true
        retryJob?.cancel()
        retryJob = null
        client?.close()
        client = null
        decoder?.stop()
        decoder = null
    }

    override fun onCleared() {
        disconnect()
        super.onCleared()
    }

    // MARK: - Girdi

    fun move(x: Float, y: Float) {
        client?.sendInput(Wire.inputMove(x, y))
    }

    fun button(x: Float, y: Float, button: Int, down: Boolean, clickCount: Int) {
        client?.sendInput(Wire.inputButton(x, y, button, down, clickCount))
    }

    fun scroll(dx: Float, dy: Float) {
        client?.sendInput(Wire.inputScroll(dx, dy))
    }

    fun key(code: Int, down: Boolean, meta: Int = 0) {
        client?.sendInput(Wire.inputKey(code, down, meta))
    }

    fun text(value: String) {
        if (value.isNotEmpty()) client?.sendInput(Wire.inputText(value))
    }
}
