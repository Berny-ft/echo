package com.echo.dictation.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.lifecycleScope
import com.echo.dictation.EchoApp
import com.echo.dictation.overlay.OverlayService
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { EchoTheme { EchoRoot() } }
        handleSelfTest()
    }

    override fun onResume() {
        super.onResume()
        // Starting the microphone service is only allowed while Echo is in the foreground.
        OverlayService.startIfEnabled(this)
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleSelfTest()
    }

    /** `adb shell am start -n com.echo.dictation/.ui.MainActivity --es selftest /sdcard/Android/data/com.echo.dictation/files/x.wav` */
    private fun handleSelfTest() {
        val path = intent?.getStringExtra("selftest") ?: return
        intent.removeExtra("selftest")
        lifecycleScope.launch { SelfTest.run(application as EchoApp, path) }
    }
}

private enum class Tab(val label: String, val icon: ImageVector) {
    Home("Home", Icons.Filled.Home),
    Style("Style", Icons.Filled.Star),
    Dictionary("Dictionary", Icons.Filled.Edit),
    History("History", Icons.Filled.List),
    Settings("Settings", Icons.Filled.Settings),
}

@Composable
private fun EchoRoot() {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    Scaffold(
        bottomBar = {
            NavigationBar {
                Tab.entries.forEachIndexed { i, t ->
                    NavigationBarItem(
                        selected = tab == i, onClick = { tab = i },
                        icon = { Icon(t.icon, contentDescription = null) }, label = { Text(t.label) },
                    )
                }
            }
        },
    ) { padding ->
        val m = Modifier.padding(padding)
        when (Tab.entries[tab]) {
            Tab.Home -> HomeScreen(m)
            Tab.Style -> StyleScreen(m)
            Tab.Dictionary -> DictionaryScreen(m)
            Tab.History -> HistoryScreen(m)
            Tab.Settings -> SettingsScreen(m)
        }
    }
}

@Composable
fun EchoTheme(content: @Composable () -> Unit) {
    val ctx = LocalContext.current
    val scheme = if (isSystemInDarkTheme()) dynamicDarkColorScheme(ctx) else dynamicLightColorScheme(ctx)
    MaterialTheme(colorScheme = scheme, content = content)
}
