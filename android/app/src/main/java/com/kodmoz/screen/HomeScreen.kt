package com.kodmoz.screen

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForwardIos
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Computer
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Usb
import androidx.compose.material.icons.rounded.Wifi
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import kotlinx.coroutines.delay

private const val REPO_URL = "https://github.com/hasanislamoglu5361/kodmoz-screen"

@Composable
fun AppMark(size: Int = 64) {
    Box(
        modifier = Modifier
            .size(size.dp)
            .clip(RoundedCornerShape((size * 0.28f).dp))
            .background(
                Brush.linearGradient(
                    listOf(Color(0xFF5B4BE0), Color(0xFF9B5CF0))
                )
            ),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = Icons.Rounded.Computer,
            contentDescription = null,
            tint = Color.White,
            modifier = Modifier.size((size * 0.5f).dp),
        )
    }
}

@Composable
fun HomeScreen(onConnect: (SessionViewModel.Target) -> Unit) {
    val context = LocalContext.current
    val store = remember { SettingsStore(context) }
    val discovery = remember { NsdDiscovery(context) }
    val focusManager = LocalFocusManager.current

    var peers by remember { mutableStateOf<List<Peer>>(emptyList()) }
    var scanError by remember { mutableStateOf<String?>(null) }
    var ip by remember { mutableStateOf(store.lastHost ?: "") }
    var port by remember { mutableStateOf(store.lastPort.toString()) }
    var code by remember { mutableStateOf(store.lastCode) }
    var manualError by remember { mutableStateOf<String?>(null) }
    var codeDialogPeer by remember { mutableStateOf<Peer?>(null) }
    var showSettings by remember { mutableStateOf(false) }
    var copied by remember { mutableStateOf(false) }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { }

    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val permission = Manifest.permission.NEARBY_WIFI_DEVICES
            if (ContextCompat.checkSelfPermission(context, permission) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                permissionLauncher.launch(permission)
            }
        }
    }

    DisposableEffect(Unit) {
        discovery.onPeers = { peers = it }
        discovery.onError = { scanError = it }
        discovery.start()
        onDispose { discovery.stop() }
    }

    LaunchedEffect(copied) {
        if (copied) {
            delay(1_500)
            copied = false
        }
    }

    fun connect(host: String, portValue: Int, codeValue: String, name: String) {
        val trimmedHost = host.trim()
        val trimmedCode = codeValue.trim()
        if (trimmedHost.isEmpty()) {
            manualError = "IP adresi veya ana bilgisayar adı girin."
            return
        }
        if (portValue !in 1..65535) {
            manualError = "Port 1–65535 arasında olmalı."
            return
        }
        if (trimmedCode.isNotEmpty() && (trimmedCode.length != 4 || trimmedCode.any { !it.isDigit() })) {
            manualError = "Eşleşme kodu 4 haneli olmalı."
            return
        }
        manualError = null
        focusManager.clearFocus()
        store.saveConnection(trimmedHost, portValue, trimmedCode)
        onConnect(
            SessionViewModel.Target(
                host = trimmedHost,
                port = portValue,
                code = trimmedCode,
                name = name.ifBlank { trimmedHost },
            )
        )
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(
                        Color(0xFF0B0D16),
                        Color(0xFF141028),
                        Color(0xFF0B0D16),
                    )
                )
            )
    ) {
        LazyColumn(
            modifier = Modifier
                .widthIn(max = 920.dp)
                .align(Alignment.TopCenter)
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding(),
            contentPadding = PaddingValues(horizontal = 28.dp, vertical = 22.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    AppMark(62)
                    Spacer(Modifier.width(16.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            "Kodmoz Screen",
                            style = MaterialTheme.typography.displaySmall,
                            color = KodmozText,
                        )
                        Text(
                            "Tabletini Mac'in için ikinci ekran yap",
                            style = MaterialTheme.typography.bodyMedium,
                            color = KodmozTextDim,
                        )
                    }
                    IconButton(onClick = { showSettings = true }) {
                        Icon(
                            Icons.Rounded.Settings,
                            contentDescription = "Ayarlar",
                            tint = KodmozTextDim,
                        )
                    }
                }
            }

            item {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .size(7.dp)
                            .clip(CircleShape)
                            .background(KodmozTeal)
                    )
                    Text(
                        "Aynı WiFi ağındaki Mac'ler otomatik bulunur",
                        style = MaterialTheme.typography.bodyMedium,
                        color = KodmozTextDim,
                    )
                    Spacer(Modifier.weight(1f))
                    IconButton(onClick = {
                        scanError = null
                        discovery.stop()
                        discovery.start()
                    }) {
                        Icon(
                            Icons.Rounded.Refresh,
                            contentDescription = "Yenile",
                            tint = KodmozTextDim,
                        )
                    }
                }
            }

            item {
                SectionTitle("MAC'LER")
            }

            if (peers.isEmpty()) {
                item {
                    Card(
                        colors = CardDefaults.cardColors(containerColor = KodmozSurface),
                        shape = RoundedCornerShape(18.dp),
                        border = BorderStroke(1.dp, KodmozOutline),
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(18.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(14.dp),
                        ) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(20.dp),
                                strokeWidth = 2.dp,
                                color = KodmozPurple,
                            )
                            Column {
                                Text(
                                    if (scanError != null) "Ağ taraması sorunu" else "Aranıyor…",
                                    style = MaterialTheme.typography.titleMedium,
                                    color = KodmozText,
                                )
                                Text(
                                    scanError ?: "Mac'te Kodmoz Screen açık olmalı. Bulunamazsa adresi elle girin.",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = KodmozTextDim,
                                )
                            }
                        }
                    }
                }
            } else {
                items(peers, key = { it.name }) { peer ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { codeDialogPeer = peer },
                        colors = CardDefaults.cardColors(containerColor = KodmozSurface),
                        shape = RoundedCornerShape(18.dp),
                        border = BorderStroke(1.dp, KodmozOutline),
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 18.dp, vertical = 16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(14.dp),
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(42.dp)
                                    .clip(CircleShape)
                                    .background(Color(0xFF26224F)),
                                contentAlignment = Alignment.Center,
                            ) {
                                Icon(
                                    Icons.Rounded.Computer,
                                    contentDescription = null,
                                    tint = KodmozPurple,
                                )
                            }
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    peer.name,
                                    style = MaterialTheme.typography.titleMedium,
                                    color = KodmozText,
                                )
                                Text(
                                    "${peer.host}:${peer.port}",
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontFamily = FontFamily.Monospace,
                                    color = KodmozTextDim,
                                )
                            }
                            Icon(
                                Icons.AutoMirrored.Rounded.ArrowForwardIos,
                                contentDescription = null,
                                tint = KodmozTextDim,
                                modifier = Modifier.size(14.dp),
                            )
                        }
                    }
                }
            }

            item {
                ManualConnectCard(
                    ip = ip,
                    port = port,
                    code = code,
                    error = manualError,
                    onIpChange = { ip = it },
                    onPortChange = { port = it },
                    onCodeChange = { code = it },
                    onConnect = {
                        connect(ip, port.toIntOrNull() ?: 0, code, ip)
                    },
                )
            }

            item {
                UsbCard(
                    port = port.toIntOrNull() ?: 9280,
                    copied = copied,
                    onCopy = {
                        copyToClipboard(
                            context,
                            "adb reverse tcp:${port.toIntOrNull() ?: 9280} tcp:${port.toIntOrNull() ?: 9280}"
                        )
                        copied = true
                    },
                    onUseLocalhost = {
                        ip = "127.0.0.1"
                        port = "9280"
                        manualError = null
                    },
                )
            }

            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        "v${BuildConfig.VERSION_NAME} · MIT",
                        style = MaterialTheme.typography.bodyMedium,
                        color = KodmozTextDim,
                    )
                    Spacer(Modifier.weight(1f))
                    TextButton(onClick = {
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(REPO_URL)))
                    }) {
                        Text("GitHub", color = KodmozPurple)
                    }
                }
            }
        }
    }

    codeDialogPeer?.let { peer ->
        PeerCodeDialog(
            peer = peer,
            initialCode = store.codeFor(peer.host) ?: store.lastCode,
            onDismiss = { codeDialogPeer = null },
            onConnect = { value ->
                codeDialogPeer = null
                connect(peer.host, peer.port, value, peer.name)
            },
        )
    }

    if (showSettings) {
        SettingsDialog(store = store, onDismiss = { showSettings = false })
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        letterSpacing = 1.6.sp,
        color = KodmozTextDim,
    )
}

@Composable
private fun ManualConnectCard(
    ip: String,
    port: String,
    code: String,
    error: String?,
    onIpChange: (String) -> Unit,
    onPortChange: (String) -> Unit,
    onCodeChange: (String) -> Unit,
    onConnect: () -> Unit,
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = KodmozSurface),
        shape = RoundedCornerShape(18.dp),
        border = BorderStroke(1.dp, KodmozOutline),
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Wifi, contentDescription = null, tint = KodmozTeal)
                Spacer(Modifier.width(10.dp))
                Text("Elle bağlan", style = MaterialTheme.typography.titleMedium)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = ip,
                    onValueChange = onIpChange,
                    label = { Text("IP adresi") },
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(12.dp),
                )
                OutlinedTextField(
                    value = port,
                    onValueChange = { value ->
                        if (value.all { it.isDigit() } && value.length <= 5) onPortChange(value)
                    },
                    label = { Text("Port") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.width(108.dp),
                    shape = RoundedCornerShape(12.dp),
                )
            }

            OutlinedTextField(
                value = code,
                onValueChange = { value ->
                    if (value.all { it.isDigit() } && value.length <= 4) onCodeChange(value)
                },
                label = { Text("Eşleşme kodu") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                supportingText = {
                    Text("Mac ekranındaki 4 hane. Kod kapalıysa boş bırakın.")
                },
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
            )

            if (error != null) {
                Text(
                    error,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error,
                )
            }

            Button(
                onClick = onConnect,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(50.dp),
                shape = RoundedCornerShape(14.dp),
            ) {
                Icon(Icons.Rounded.Link, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Bağlan")
            }
        }
    }
}

@Composable
private fun UsbCard(
    port: Int,
    copied: Boolean,
    onCopy: () -> Unit,
    onUseLocalhost: () -> Unit,
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Color(0xFF121528)),
        shape = RoundedCornerShape(18.dp),
        border = BorderStroke(1.dp, KodmozOutline),
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Usb, contentDescription = null, tint = KodmozTextDim)
                Spacer(Modifier.width(10.dp))
                Text("USB ile bağlanmak", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.weight(1f))
                TextButton(onClick = onCopy) {
                    Icon(
                        if (copied) Icons.Rounded.Check else Icons.Rounded.ContentCopy,
                        contentDescription = null,
                        modifier = Modifier.size(15.dp),
                    )
                    Spacer(Modifier.width(5.dp))
                    Text(if (copied) "Kopyalandı" else "Kopyala")
                }
            }
            Text(
                "adb reverse tcp:$port tcp:$port",
                fontFamily = FontFamily.Monospace,
                fontSize = 13.sp,
                color = KodmozTeal,
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .background(Color.Black.copy(alpha = 0.35f))
                    .padding(horizontal = 12.dp, vertical = 10.dp),
            )
            Text(
                "Mac'te bu komutu çalıştırın (USB hata ayıklama açık olmalı), sonra 127.0.0.1 adresini kullanın.",
                style = MaterialTheme.typography.bodyMedium,
                color = KodmozTextDim,
            )
            TextButton(onClick = onUseLocalhost, contentPadding = PaddingValues(0.dp)) {
                Text("USB adresini forma doldur", color = KodmozPurple)
            }
        }
    }
}

@Composable
private fun PeerCodeDialog(
    peer: Peer,
    initialCode: String,
    onDismiss: () -> Unit,
    onConnect: (String) -> Unit,
) {
    var code by remember { mutableStateOf(initialCode) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Eşleşme kodu") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(peer.name, style = MaterialTheme.typography.titleMedium)
                Text(
                    "${peer.host}:${peer.port}",
                    style = MaterialTheme.typography.bodyMedium,
                    fontFamily = FontFamily.Monospace,
                    color = KodmozTextDim,
                )
                OutlinedTextField(
                    value = code,
                    onValueChange = {
                        if (it.all { c -> c.isDigit() } && it.length <= 4) code = it
                    },
                    label = { Text("4 haneli kod") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(
                    "Kod, Mac ekranının “Tabletten bağlan” kartında yazar.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = KodmozTextDim,
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onConnect(code.trim()) },
                enabled = code.length == 4,
            ) { Text("Bağlan") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("İptal") }
        },
        containerColor = KodmozSurface,
    )
}

@Composable
private fun SettingsDialog(store: SettingsStore, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var showStats by remember { mutableStateOf(store.showStats) }
    var keepAwake by remember { mutableStateOf(store.keepAwake) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Ayarlar") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                SwitchRow("İstatistikleri göster", showStats) {
                    showStats = it
                    store.showStats = it
                }
                SwitchRow("Ekranı açık tut", keepAwake) {
                    keepAwake = it
                    store.keepAwake = it
                }
                HorizontalDivider(
                    modifier = Modifier.padding(vertical = 10.dp),
                    color = KodmozOutline,
                )
                Text(
                    "Kodmoz Screen v${BuildConfig.VERSION_NAME}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = KodmozText,
                )
                Text(
                    "Sanal ekran, donanım hızlandırmalı H.264 ve düşük gecikmeli TCP. MIT lisansı.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = KodmozTextDim,
                )
                TextButton(
                    onClick = {
                        context.startActivity(
                            Intent(Intent.ACTION_VIEW, Uri.parse(REPO_URL))
                        )
                    },
                    contentPadding = PaddingValues(0.dp),
                ) {
                    Text("github.com/hasanislamoglu5361/kodmoz-screen", color = KodmozPurple)
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Kapat") }
        },
        containerColor = KodmozSurface,
    )
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onChange(!checked) }
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.weight(1f),
        )
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

private fun copyToClipboard(context: Context, value: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
    clipboard?.setPrimaryClip(ClipData.newPlainText("Kodmoz Screen", value))
}
