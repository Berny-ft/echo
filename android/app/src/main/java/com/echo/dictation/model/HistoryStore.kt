package com.echo.dictation.model

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

data class HistoryItem(
    val time: Long,
    val text: String,
    val raw: String,
    val engine: String,
    val app: String?,
    val audioSeconds: Double,
    val processingMs: Long,
)

/** The last [LIMIT] dictations, as JSON in app-private storage. */
class HistoryStore(context: Context) {
    private val file = File(context.filesDir, "history.json")
    private val _items = MutableStateFlow(load())
    val items: StateFlow<List<HistoryItem>> = _items

    @Synchronized
    fun add(item: HistoryItem) {
        _items.value = (listOf(item) + _items.value).take(LIMIT)
        save()
    }

    @Synchronized
    fun clear() {
        _items.value = emptyList()
        save()
    }

    private fun save() {
        val arr = JSONArray(_items.value.map {
            JSONObject().put("time", it.time).put("text", it.text).put("raw", it.raw).put("engine", it.engine)
                .put("app", it.app).put("audioSeconds", it.audioSeconds).put("processingMs", it.processingMs)
        })
        file.writeText(arr.toString())
    }

    private fun load(): List<HistoryItem> = runCatching {
        val arr = JSONArray(file.readText())
        (0 until arr.length()).map {
            val o = arr.getJSONObject(it)
            HistoryItem(o.getLong("time"), o.getString("text"), o.optString("raw"), o.optString("engine"),
                o.optString("app").ifEmpty { null }, o.optDouble("audioSeconds"), o.optLong("processingMs"))
        }
    }.getOrDefault(emptyList())

    companion object { const val LIMIT = 200 }
}
