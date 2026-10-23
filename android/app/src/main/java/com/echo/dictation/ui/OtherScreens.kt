package com.echo.dictation.ui

import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.echo.dictation.model.Catalog
import com.echo.dictation.model.FormatStyle
import com.echo.dictation.model.ModelInfo
import com.echo.dictation.model.ModelState
import com.echo.dictation.model.Prefs
import com.echo.dictation.model.Replacement
import java.text.DateFormat
import java.util.Date

@Composable
fun StyleScreen(modifier: Modifier) {
    val app = echoApp()
    val s = settingsState()
    Page("Style", modifier) {
        Hint("How Echo shapes what you say. Smart switches to Email in mail apps and Message in chat apps.")
        Section {
            FormatStyle.entries.forEach { style ->
                Choice(style.title, style.subtitle, s.style == style) { app.prefs.update { copy(style = style) } }
            }
        }
        if (s.formatterModel == Catalog.FORMATTER_OFF) {
            Hint("Styles beyond cleanup need a formatting model. Download one in Settings.")
        }
    }
}

@Composable
fun DictionaryScreen(modifier: Modifier) {
    val app = echoApp()
    val s = settingsState()
    Page("Dictionary", modifier) {
        Section("Vocabulary") {
            Hint("Names and terms Echo should spell exactly like this. One per line.")
            var vocab by remember { mutableStateOf(s.vocabulary.joinToString("\n")) }
            OutlinedTextField(
                value = vocab,
                onValueChange = { vocab = it; app.prefs.update { copy(vocabulary = Prefs.parseVocabulary(it)) } },
                modifier = Modifier.fillMaxWidth().heightIn(min = 120.dp),
                placeholder = { Text("Berny\nPixel\nWhisperKit") },
            )
        }
        Section("Replacements") {
            Hint("When you say the phrase on the left, Echo writes the text on the right.")
            s.replacements.forEachIndexed { i, r ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(r.spoken, style = MaterialTheme.typography.bodyLarge)
                        Hint("→ ${r.written}")
                    }
                    IconButton(onClick = { app.prefs.update { copy(replacements = replacements.filterIndexed { j, _ -> j != i }) } }) {
                        Icon(Icons.Filled.Delete, "Remove")
                    }
                }
            }
            var spoken by remember { mutableStateOf("") }
            var written by remember { mutableStateOf("") }
            OutlinedTextField(spoken, { spoken = it }, Modifier.fillMaxWidth(), label = { Text("When I say") }, singleLine = true)
            OutlinedTextField(written, { written = it }, Modifier.fillMaxWidth(), label = { Text("Write") }, singleLine = true)
            OutlinedButton(
                enabled = spoken.isNotBlank() && written.isNotBlank(),
                onClick = {
                    app.prefs.update { copy(replacements = replacements + Replacement(spoken.trim(), written.trim())) }
                    spoken = ""; written = ""
                },
            ) { Text("Add") }
        }
    }
}

@Composable
fun HistoryScreen(modifier: Modifier) {
    val app = echoApp()
    val ctx = LocalContext.current
    val items by app.history.items.collectAsState()
    Page("History", modifier) {
        if (items.isEmpty()) Hint("Your dictations show up here. Tap one to copy it.")
        else TextButton(onClick = { app.history.clear() }) { Text("Clear history") }
        items.forEach { item ->
            Section {
                Column(Modifier.fillMaxWidth().clickable {
                    app.copyToClipboard(item.text)
                    Toast.makeText(ctx, "Copied", Toast.LENGTH_SHORT).show()
                }, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(item.text, style = MaterialTheme.typography.bodyLarge)
                    Hint(listOfNotNull(
                        DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(item.time)),
                        item.app, "%.1f s audio".format(item.audioSeconds), "%.1f s to process".format(item.processingMs / 1000.0), item.engine,
                    ).joinToString(" · "))
                }
            }
        }
    }
}

@Composable
fun SettingsScreen(modifier: Modifier) {
    val app = echoApp()
    val s = settingsState()
    val states by app.models.states.collectAsState()
    Page("Settings", modifier) {
        Section("Speech model") {
            Catalog.speech.forEach { m ->
                ModelChoice(m, states[m.id] ?: ModelState.Missing, selected = s.speechModel == m.id,
                    onSelect = { app.prefs.update { copy(speechModel = m.id) } })
            }
        }
        Section("Formatting") {
            Hint("A small language model on your phone rewrites the transcript in your chosen style. Nothing leaves the device.")
            Choice("Basic cleanup only", "Removes fillers, fixes capitalization. Instant.", s.formatterModel == Catalog.FORMATTER_OFF) {
                app.prefs.update { copy(formatterModel = Catalog.FORMATTER_OFF) }
            }
            Catalog.formatters.forEach { m ->
                ModelChoice(m, states[m.id] ?: ModelState.Missing, selected = s.formatterModel == m.id,
                    onSelect = { app.prefs.update { copy(formatterModel = m.id) } })
            }
        }
        Section("Language") {
            val englishOnly = Catalog.find(s.speechModel)?.englishOnly == true
            var open by remember { mutableStateOf(false) }
            OutlinedButton(onClick = { open = true }, enabled = !englishOnly) {
                Text(if (englishOnly) "English" else Prefs.languages.firstOrNull { it.first == s.language }?.second ?: s.language)
            }
            DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                Prefs.languages.forEach { (code, name) ->
                    DropdownMenuItem(text = { Text(name) }, onClick = { open = false; app.prefs.update { copy(language = code) } })
                }
            }
            if (englishOnly) Hint("This speech model only understands English. Pick a multilingual one for other languages.")
        }
        Section("Bubble") {
            Toggle("Only show while typing", "Hide the bubble unless a text field is focused", s.onlyWhenTyping) {
                app.prefs.update { copy(onlyWhenTyping = it) }
            }
            Toggle("Haptics", "Vibrate when recording starts and stops", s.haptics) { app.prefs.update { copy(haptics = it) } }
            Hint("Drag the bubble to move it. Long-press it to open Echo.")
        }
    }
}

@Composable
private fun Choice(title: String, detail: String, selected: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
        RadioButton(selected = selected, onClick = onClick)
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Hint(detail)
        }
    }
}

@Composable
private fun ModelChoice(m: ModelInfo, state: ModelState, selected: Boolean, onSelect: () -> Unit) {
    val app = echoApp()
    Column {
        HorizontalDivider()
        Row(Modifier.fillMaxWidth().padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            RadioButton(selected = selected, onClick = onSelect)
            Column(Modifier.weight(1f).clickable(onClick = onSelect)) {
                Text("${m.title} · ${m.sizeLabel}", style = MaterialTheme.typography.bodyLarge)
                Hint(m.detail)
            }
        }
        Row(Modifier.padding(start = 48.dp)) {
            ModelStep(
                title = when (state) { ModelState.Ready -> "Downloaded"; else -> "Not downloaded" },
                size = m.sizeLabel, state = state,
                onDownload = { app.models.download(m); onSelect() }, onCancel = { app.models.cancel(m) },
            )
        }
        if (state == ModelState.Ready && !selected) TextButton(onClick = { app.models.delete(m) }, modifier = Modifier.padding(start = 40.dp)) {
            Text("Delete to free ${m.sizeLabel}")
        }
    }
}

@Composable
private fun Toggle(title: String, detail: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Hint(detail)
        }
        Switch(checked = checked, onCheckedChange = onChange)
    }
}
