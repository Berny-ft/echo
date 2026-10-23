package com.echo.dictation.model

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File

sealed interface ModelState {
    data object Missing : ModelState
    data class Downloading(val fraction: Float) : ModelState
    data object Ready : ModelState
    data class Failed(val reason: String) : ModelState
}

/**
 * Downloads models with the system DownloadManager, which survives the app going to the
 * background and resumes over flaky connections. Files land in app-private external storage.
 */
class ModelStore(private val context: Context) {
    private val dm = context.getSystemService(DownloadManager::class.java)
    private val dir = File(context.getExternalFilesDir(null), "models").apply { mkdirs() }
    private val prefs = context.getSharedPreferences("downloads", Context.MODE_PRIVATE)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val watchers = mutableMapOf<String, Job>()

    private val _states = MutableStateFlow(Catalog.all.associate { it.id to initialState(it) })
    val states: StateFlow<Map<String, ModelState>> = _states

    init {
        Catalog.all.filter { prefs.contains(it.id) }.forEach { watch(it, prefs.getLong(it.id, -1)) }
    }

    fun file(model: ModelInfo) = File(dir, model.fileName)
    fun isReady(id: String) = _states.value[id] == ModelState.Ready
    fun pathIfReady(id: String): String? = Catalog.find(id)?.takeIf { isReady(id) }?.let { file(it).absolutePath }

    fun download(model: ModelInfo) {
        if (_states.value[model.id] is ModelState.Downloading || isReady(model.id)) return
        val part = File(dir, model.fileName + ".part").apply { delete() }
        val request = DownloadManager.Request(Uri.parse(model.url))
            .setTitle("Echo: ${model.title}")
            .setDescription(model.sizeLabel)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setDestinationUri(Uri.fromFile(part))
            .setAllowedOverMetered(true)
        val id = dm.enqueue(request)
        prefs.edit().putLong(model.id, id).apply()
        set(model.id, ModelState.Downloading(0f))
        watch(model, id)
    }

    fun cancel(model: ModelInfo) {
        watchers.remove(model.id)?.cancel()
        prefs.getLong(model.id, -1).takeIf { it >= 0 }?.let { dm.remove(it) }
        finish(model, ModelState.Missing)
    }

    fun delete(model: ModelInfo) {
        cancel(model)
        file(model).delete()
        set(model.id, ModelState.Missing)
    }

    private fun watch(model: ModelInfo, id: Long) {
        watchers[model.id]?.cancel()
        watchers[model.id] = scope.launch {
            while (isActive) {
                val c = dm.query(DownloadManager.Query().setFilterById(id))
                if (c == null || !c.moveToFirst()) { c?.close(); finish(model, ModelState.Missing); return@launch }
                val status = c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                val done = c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                val total = c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)).takeIf { it > 0 } ?: model.bytes
                val reason = c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
                c.close()
                when (status) {
                    DownloadManager.STATUS_SUCCESSFUL -> {
                        val part = File(dir, model.fileName + ".part")
                        val ok = part.exists() && part.renameTo(file(model))
                        finish(model, if (ok) ModelState.Ready else ModelState.Failed("Couldn't save the file"))
                        return@launch
                    }
                    DownloadManager.STATUS_FAILED -> {
                        finish(model, ModelState.Failed("Download failed (error $reason)"))
                        return@launch
                    }
                    else -> set(model.id, ModelState.Downloading((done.toFloat() / total).coerceIn(0f, 1f)))
                }
                delay(500)
            }
        }
    }

    private fun finish(model: ModelInfo, state: ModelState) {
        prefs.edit().remove(model.id).apply()
        watchers.remove(model.id)
        set(model.id, state)
    }

    private fun set(id: String, state: ModelState) = _states.update { it + (id to state) }

    private fun initialState(model: ModelInfo): ModelState =
        if (file(model).let { it.exists() && it.length() > 0 }) ModelState.Ready
        else if (prefs.contains(model.id)) ModelState.Downloading(0f)
        else ModelState.Missing
}
