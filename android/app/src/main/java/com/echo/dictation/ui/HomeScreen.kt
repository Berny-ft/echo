package com.echo.dictation.ui

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.echo.dictation.model.Catalog
import com.echo.dictation.model.ModelState
import com.echo.dictation.overlay.EchoAccessibilityService
import com.echo.dictation.overlay.OverlayService

@Composable
fun HomeScreen(modifier: Modifier) {
    val ctx = LocalContext.current
    val app = echoApp()
    val settings = settingsState()
    val modelStates by app.models.states.collectAsState()

    // Permission states only change in system Settings, so re-read them whenever Echo comes back.
    var tick by remember { mutableIntStateOf(0) }
    val owner = LocalLifecycleOwner.current
    DisposableEffect(owner) {
        val obs = LifecycleEventObserver { _, e -> if (e == Lifecycle.Event.ON_RESUME) tick++ }
        owner.lifecycle.addObserver(obs)
        onDispose { owner.lifecycle.removeObserver(obs) }
    }
    val mic = remember(tick) { ctx.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED }
    val notif = remember(tick) { ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED }
    val overlay = remember(tick) { Settings.canDrawOverlays(ctx) }
    val access = remember(tick) { accessibilityEnabled(ctx) }
    val speech = Catalog.find(settings.speechModel) ?: Catalog.speech.first()
    val speechState = modelStates[speech.id] ?: ModelState.Missing

    val askPermissions = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { tick++ }
    val ready = mic && overlay && speechState == ModelState.Ready

    Page("Echo", modifier) {
        Section {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Dictation bubble", style = MaterialTheme.typography.titleMedium)
                    Hint(when {
                        !ready -> "Finish setup below to turn it on."
                        settings.bubbleEnabled -> "Tap the bubble in any app to start, tap again to finish."
                        else -> "Off"
                    })
                }
                Switch(
                    checked = settings.bubbleEnabled && ready,
                    enabled = ready,
                    onCheckedChange = { on ->
                        app.prefs.update { copy(bubbleEnabled = on) }
                        if (on) OverlayService.startIfEnabled(ctx) else OverlayService.stop(ctx)
                    },
                )
            }
        }

        Section("Setup") {
            Step("Microphone", "To hear you", mic) {
                askPermissions.launch(arrayOf(Manifest.permission.RECORD_AUDIO, Manifest.permission.POST_NOTIFICATIONS))
            }
            Step("Display over other apps", "To show the bubble", overlay) {
                ctx.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${ctx.packageName}")))
            }
            Step("Type into apps", "Accessibility service that puts the text in the field you're editing", access) {
                ctx.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            }
            if (!access) {
                Hint("If Android says the setting is restricted: open App info for Echo, tap ⋮ in the corner, choose \"Allow restricted settings\", then try again. Without it, Echo copies the text so you can paste it.")
                FilledTonalButton(onClick = {
                    ctx.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${ctx.packageName}")))
                }) { Text("Open App info") }
            }
            if (!notif) Step("Notifications", "Optional: shows that the bubble is running", false) {
                askPermissions.launch(arrayOf(Manifest.permission.POST_NOTIFICATIONS))
            }
            ModelStep(speech.title + " speech model", speech.sizeLabel, speechState,
                onDownload = { app.models.download(speech) }, onCancel = { app.models.cancel(speech) })
        }

        Section("Try it") {
            var text by remember { mutableStateOf("") }
            OutlinedTextField(
                value = text, onValueChange = { text = it },
                modifier = Modifier.fillMaxWidth().heightIn(min = 120.dp),
                placeholder = { Text("Tap here, then tap the bubble and speak") },
            )
            Hint("Formatting: " + (Catalog.find(settings.formatterModel)?.title?.let { "$it (on device)" } ?: "basic cleanup") + " · Style: " + settings.style.title)
        }
    }
}

@Composable
private fun Step(title: String, detail: String, done: Boolean, action: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Hint(detail)
        }
        if (done) Icon(Icons.Filled.CheckCircle, "Done", tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(28.dp))
        else Button(onClick = action) { Text("Allow") }
    }
}

@Composable
fun ModelStep(title: String, size: String, state: ModelState, onDownload: () -> Unit, onCancel: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.bodyLarge)
                Hint(when (state) {
                    ModelState.Ready -> "Downloaded · runs on this phone"
                    is ModelState.Downloading -> "Downloading… ${(state.fraction * 100).toInt()}% of $size"
                    is ModelState.Failed -> state.reason
                    ModelState.Missing -> "$size download, one time"
                })
            }
            when (state) {
                ModelState.Ready -> Icon(Icons.Filled.CheckCircle, "Done", tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(28.dp))
                is ModelState.Downloading -> FilledTonalButton(onClick = onCancel) { Text("Cancel") }
                else -> Button(onClick = onDownload) { Text("Download") }
            }
        }
        if (state is ModelState.Downloading) LinearProgressIndicator(progress = { state.fraction }, modifier = Modifier.fillMaxWidth())
    }
}

private fun accessibilityEnabled(ctx: Context): Boolean {
    if (EchoAccessibilityService.instance != null) return true
    val am = ctx.getSystemService(AccessibilityManager::class.java)
    return am.getEnabledAccessibilityServiceList(android.accessibilityservice.AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
        .any { it.resolveInfo.serviceInfo.packageName == ctx.packageName }
}
