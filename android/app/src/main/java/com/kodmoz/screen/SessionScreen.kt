package com.kodmoz.screen

import android.app.Activity
import android.app.Application
import android.content.ClipboardManager
import android.content.Context
import android.content.ContextWrapper
import android.view.KeyEvent
import android.view.Surface
import android.view.TextureView
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material.icons.rounded.Keyboard
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.AssistChip
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay

@Composable
fun SessionScreen(
    target: SessionViewModel.Target,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val application = context.applicationContext as Application
    val settings = remember { SettingsStore(context) }
    val vm: SessionViewModel = viewModel(
        key = "session-${target.id}",
        factory = object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T {
                return SessionViewModel(application, target) as T
            }
        }
    )
    val state by vm.state.collectAsState()
    var showKeyboard by remember { mutableStateOf(false) }
    var showHint by remember { mutableStateOf(true) }

    val activity = context.findActivity()
    DisposableEffect(Unit) {
        val window = activity?.window
        val controller = window?.let {
            WindowCompat.getInsetsController(it, it.decorView)
        }
        controller?.hide(WindowInsetsCompat.Type.systemBars())
        controller?.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        onDispose {
            controller?.show(WindowInsetsCompat.Type.systemBars())
            vm.disconnect()
        }
    }

    BackHandler(enabled = !showKeyboard) {
        vm.disconnect()
        onBack()
    }

    LaunchedEffect(state.phase) {
        if (state.phase == SessionViewModel.Phase.Streaming) {
            showHint = true
            delay(6_000)
            showHint = false
        }
    }

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
    ) {
        val aspect = if (state.width > 0 && state.height > 0) {
            state.width.toFloat() / state.height
        } else {
            16f / 10f
        }
        val availableAspect = maxWidth.value / maxHeight.value
        val videoWidth = if (availableAspect > aspect) maxHeight * aspect else maxWidth
        val videoHeight = videoWidth / aspect

        Box(
            modifier = Modifier
                .width(videoWidth)
                .height(videoHeight)
                .align(Alignment.Center)
        ) {
            AndroidSurface(
                keepAwake = settings.keepAwake,
                onSurface = { vm.attachSurface(it) },
                onSurfaceDestroyed = { vm.detachSurface() },
                onMove = { x, y -> vm.move(x, y) },
                onButton = { x, y, down, clicks -> vm.button(x, y, 0, down, clicks) },
                onScroll = { dx, dy -> vm.scroll(dx, dy) },
            )
        }

        if (settings.showStats && state.phase == SessionViewModel.Phase.Streaming) {
            StatsPill(
                state = state,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(14.dp),
            )
        }

        IconButton(
            onClick = {
                vm.disconnect()
                onBack()
            },
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(14.dp)
                .size(42.dp)
                .clip(CircleShape)
                .background(Color.Black.copy(alpha = 0.55f))
        ) {
            Icon(
                Icons.Rounded.Close,
                contentDescription = "Bağlantıyı kapat",
                tint = Color.White,
            )
        }

        if (state.phase == SessionViewModel.Phase.Streaming) {
            IconButton(
                onClick = { showKeyboard = true },
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(18.dp)
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.55f))
            ) {
                Icon(
                    Icons.Rounded.Keyboard,
                    contentDescription = "Klavye",
                    tint = Color.White,
                )
            }
        }

        if (state.phase != SessionViewModel.Phase.Streaming) {
            ConnectionOverlay(
                state = state,
                target = target,
                onRetry = { vm.retry() },
                onBack = {
                    vm.disconnect()
                    onBack()
                },
            )
        }

        if (state.phase == SessionViewModel.Phase.Streaming && showHint) {
            Text(
                "Tek dokunuş tıklama · uzun basıp sürükleme · iki parmak kaydırma",
                style = MaterialTheme.typography.bodyMedium,
                color = Color.White.copy(alpha = 0.85f),
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 26.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(Color.Black.copy(alpha = 0.55f))
                    .padding(horizontal = 14.dp, vertical = 8.dp)
            )
        }
    }

    if (showKeyboard) {
        KeyboardSheet(vm = vm, onDismiss = { showKeyboard = false })
    }
}

@Composable
private fun AndroidSurface(
    keepAwake: Boolean,
    onSurface: (Surface) -> Unit,
    onSurfaceDestroyed: () -> Unit,
    onMove: (Float, Float) -> Unit,
    onButton: (Float, Float, Boolean, Int) -> Unit,
    onScroll: (Float, Float) -> Unit,
) {
    androidx.compose.ui.viewinterop.AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { context ->
            TextureView(context).apply {
                keepScreenOn = keepAwake
                val touch = ScreenTouchController(
                    onMove = onMove,
                    onButton = onButton,
                    onScroll = onScroll,
                )
                setOnTouchListener(touch)

                var surface: Surface? = null
                surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                    override fun onSurfaceTextureAvailable(
                        texture: android.graphics.SurfaceTexture,
                        width: Int,
                        height: Int,
                    ) {
                        val newSurface = Surface(texture)
                        surface = newSurface
                        onSurface(newSurface)
                    }

                    override fun onSurfaceTextureSizeChanged(
                        texture: android.graphics.SurfaceTexture,
                        width: Int,
                        height: Int,
                    ) {
                    }

                    override fun onSurfaceTextureDestroyed(
                        texture: android.graphics.SurfaceTexture,
                    ): Boolean {
                        onSurfaceDestroyed()
                        surface?.release()
                        surface = null
                        return true
                    }

                    override fun onSurfaceTextureUpdated(
                        texture: android.graphics.SurfaceTexture,
                    ) {
                    }
                }
            }
        },
    )
}

@Composable
private fun StatsPill(state: SessionViewModel.UiState, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(Color.Black.copy(alpha = 0.58f))
            .padding(horizontal = 12.dp, vertical = 7.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(6.dp)
                .clip(CircleShape)
                .background(Color(0xFF5BE38A))
        )
        Text(
            "${state.fps.toInt()} fps",
            color = Color.White.copy(alpha = 0.9f),
            fontSize = 11.sp,
            fontFamily = FontFamily.Monospace,
        )
        Text(
            String.format("%.1f Mbps", state.mbps),
            color = Color.White.copy(alpha = 0.65f),
            fontSize = 11.sp,
            fontFamily = FontFamily.Monospace,
        )
        if (state.rttMs >= 0) {
            Text(
                "${state.rttMs} ms",
                color = Color.White.copy(alpha = 0.65f),
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace,
            )
        }
        if (state.width > 0) {
            Text(
                "${state.width}×${state.height}",
                color = Color.White.copy(alpha = 0.65f),
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace,
            )
        }
    }
}

@Composable
private fun ConnectionOverlay(
    state: SessionViewModel.UiState,
    target: SessionViewModel.Target,
    onRetry: () -> Unit,
    onBack: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.68f))
            .pointerInput(Unit) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    // Dokunuşları yut; alttaki video katmanına geçmesin.
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier
                .width(430.dp)
                .clip(RoundedCornerShape(22.dp))
                .background(
                    Brush.verticalGradient(
                        listOf(Color(0xFF1B1E31), Color(0xFF121420))
                    )
                )
                .padding(26.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            if (state.phase == SessionViewModel.Phase.Connecting ||
                state.phase == SessionViewModel.Phase.Reconnecting
            ) {
                CircularProgressIndicator(
                    color = KodmozPurple,
                    strokeWidth = 3.dp,
                    modifier = Modifier.size(34.dp),
                )
            } else {
                Icon(
                    Icons.Rounded.ErrorOutline,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.error,
                    modifier = Modifier.size(38.dp),
                )
            }

            Text(
                when (state.phase) {
                    SessionViewModel.Phase.Connecting -> "Bağlanıyor…"
                    SessionViewModel.Phase.Streaming -> "Bağlandı"
                    SessionViewModel.Phase.Reconnecting -> "Yeniden bağlanıyor…"
                    SessionViewModel.Phase.Failed -> "Bağlantı kurulamadı"
                },
                style = MaterialTheme.typography.titleLarge,
                color = KodmozText,
            )

            Text(
                "${target.name}\n${target.host}:${target.port}",
                style = MaterialTheme.typography.bodyMedium,
                color = KodmozTextDim,
                textAlign = TextAlign.Center,
            )

            if (state.error != null) {
                Text(
                    state.error,
                    style = MaterialTheme.typography.bodyMedium,
                    color = Color(0xFFFFB4AB),
                    textAlign = TextAlign.Center,
                )
            }

            if (state.phase == SessionViewModel.Phase.Reconnecting) {
                Text(
                    "Deneme ${state.attempt}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = KodmozTextDim,
                )
            }

            Spacer(Modifier.height(2.dp))

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (state.phase == SessionViewModel.Phase.Failed ||
                    state.phase == SessionViewModel.Phase.Reconnecting
                ) {
                    Button(onClick = onRetry, shape = RoundedCornerShape(12.dp)) {
                        Icon(Icons.Rounded.Refresh, contentDescription = null)
                        Spacer(Modifier.width(6.dp))
                        Text(if (state.phase == SessionViewModel.Phase.Failed) "Yeniden Dene" else "Hemen Dene")
                    }
                }
                OutlinedButton(onClick = onBack, shape = RoundedCornerShape(12.dp)) {
                    Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = null)
                    Spacer(Modifier.width(6.dp))
                    Text("Geri")
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun KeyboardSheet(vm: SessionViewModel, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val keyboard = LocalSoftwareKeyboardController.current
    val focusRequester = remember { FocusRequester() }
    var text by remember { mutableStateOf("") }
    var previous by remember { mutableStateOf("") }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = KodmozSurface,
        dragHandle = { BottomSheetDefaults.DragHandle() },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .imePadding()
                .padding(horizontal = 22.dp)
                .padding(bottom = 30.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                "Uzaktan klavye",
                style = MaterialTheme.typography.titleLarge,
                color = KodmozText,
            )
            Text(
                "Yazdıklarınız Mac'teki etkin pencereye gider.",
                style = MaterialTheme.typography.bodyMedium,
                color = KodmozTextDim,
            )
            OutlinedTextField(
                value = text,
                onValueChange = { value ->
                    val old = previous
                    when {
                        value.startsWith(old) -> {
                            if (value.length > old.length) {
                                vm.text(value.substring(old.length))
                            }
                        }
                        old.startsWith(value) -> {
                            repeat(old.length - value.length) {
                                vm.key(KeyEvent.KEYCODE_DEL, true)
                                vm.key(KeyEvent.KEYCODE_DEL, false)
                            }
                        }
                        else -> {
                            repeat(old.length) {
                                vm.key(KeyEvent.KEYCODE_DEL, true)
                                vm.key(KeyEvent.KEYCODE_DEL, false)
                            }
                            vm.text(value)
                        }
                    }
                    previous = value
                    text = value
                },
                placeholder = { Text("Yazmaya başlayın…") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
                modifier = Modifier
                    .fillMaxWidth()
                    .focusRequester(focusRequester),
                shape = RoundedCornerShape(14.dp),
            )

            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                SpecialKey("Esc") { pressKey(vm, KeyEvent.KEYCODE_ESCAPE) }
                SpecialKey("Tab") { pressKey(vm, KeyEvent.KEYCODE_TAB) }
                SpecialKey("↵") { pressKey(vm, KeyEvent.KEYCODE_ENTER) }
                SpecialKey("⌫") { pressKey(vm, KeyEvent.KEYCODE_DEL) }
                SpecialKey("←") { pressKey(vm, KeyEvent.KEYCODE_DPAD_LEFT) }
                SpecialKey("↑") { pressKey(vm, KeyEvent.KEYCODE_DPAD_UP) }
                SpecialKey("↓") { pressKey(vm, KeyEvent.KEYCODE_DPAD_DOWN) }
                SpecialKey("→") { pressKey(vm, KeyEvent.KEYCODE_DPAD_RIGHT) }
            }

            OutlinedButton(
                onClick = {
                    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE)
                        as? ClipboardManager
                    val value = clipboard?.primaryClip
                        ?.takeIf { it.itemCount > 0 }
                        ?.getItemAt(0)
                        ?.coerceToText(context)
                        ?.toString()
                    if (!value.isNullOrEmpty()) {
                        vm.text(value)
                    }
                },
                shape = RoundedCornerShape(12.dp),
            ) {
                Icon(Icons.Rounded.ContentPaste, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Panodan gönder")
            }
        }
    }

    LaunchedEffect(Unit) {
        focusRequester.requestFocus()
    }
    DisposableEffect(Unit) {
        onDispose { keyboard?.hide() }
    }
}

@Composable
private fun SpecialKey(label: String, onClick: () -> Unit) {
    AssistChip(
        onClick = onClick,
        label = { Text(label, fontFamily = FontFamily.Monospace) },
    )
}

private fun pressKey(vm: SessionViewModel, code: Int) {
    vm.key(code, true)
    vm.key(code, false)
}

private fun Context.findActivity(): Activity? {
    var current: Context = this
    while (current is ContextWrapper) {
        if (current is Activity) return current
        current = current.baseContext
    }
    return null
}
