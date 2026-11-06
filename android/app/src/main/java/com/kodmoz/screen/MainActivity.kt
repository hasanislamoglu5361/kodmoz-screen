package com.kodmoz.screen

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.view.WindowCompat
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import android.content.Intent

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        controller.isAppearanceLightStatusBars = false
        controller.isAppearanceLightNavigationBars = false
        val initialTarget = if (BuildConfig.DEBUG) {
            intent?.getStringExtra("host")?.takeIf { it.isNotBlank() }?.let { host ->
                SessionViewModel.Target(
                    host = host,
                    port = intent.getIntExtra("port", 9280),
                    code = intent.getStringExtra("code").orEmpty(),
                    name = host,
                )
            }
        } else {
            null
        }
        setContent {
            KodmozTheme {
                KodmozApp(initialTarget)
            }
        }
    }
}

@Composable
fun KodmozApp(initialTarget: SessionViewModel.Target? = null) {
    var target by remember { mutableStateOf<SessionViewModel.Target?>(initialTarget) }
    val active = target
    if (active == null) {
        HomeScreen(onConnect = { target = it })
    } else {
        SessionScreen(
            target = active,
            onBack = { target = null },
        )
    }
}
