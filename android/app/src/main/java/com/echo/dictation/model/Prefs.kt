package com.echo.dictation.model

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject

enum class FormatStyle(val title: String, val subtitle: String) {
    SMART("Smart", "Adapts to the app you're typing in"),
    CLEAN("Clean", "Your words, minus the ums and stumbles"),
    POLISHED("Polished", "Clear, well-structured prose"),
    NOTES("Notes", "Organized bullet points"),
    EMAIL("Email", "Greeting, paragraphs, sign-off"),
    MESSAGE("Message", "Short and conversational"),
}

data class Replacement(val spoken: String, val written: String)

data class Settings(
    val style: FormatStyle,
    val speechModel: String,
    /** Id of the formatting model, or [Catalog.FORMATTER_OFF] for rule-based cleanup only. */
    val formatterModel: String,
    val language: String,
    val vocabulary: List<String>,
    val replacements: List<Replacement>,
    val bubbleEnabled: Boolean,
    val onlyWhenTyping: Boolean,
    val haptics: Boolean,
)

/** User settings in SharedPreferences, exposed as a [StateFlow] so UI and service stay in sync. */
class Prefs(context: Context) {
    private val sp: SharedPreferences = context.getSharedPreferences("echo", Context.MODE_PRIVATE)
    private val _state = MutableStateFlow(read())
    val state: StateFlow<Settings> = _state
    val current: Settings get() = _state.value

    var bubbleX: Int
        get() = sp.getInt("bubbleX", -1)
        set(v) = sp.edit().putInt("bubbleX", v).apply()
    var bubbleY: Int
        get() = sp.getInt("bubbleY", -1)
        set(v) = sp.edit().putInt("bubbleY", v).apply()

    fun update(block: Settings.() -> Settings) {
        val s = _state.value.block()
        sp.edit()
            .putString("style", s.style.name)
            .putString("speechModel", s.speechModel)
            .putString("formatterModel", s.formatterModel)
            .putString("language", s.language)
            .putString("vocabulary", s.vocabulary.joinToString("\n"))
            .putString("replacements", JSONArray(s.replacements.map {
                JSONObject().put("spoken", it.spoken).put("written", it.written)
            }).toString())
            .putBoolean("bubbleEnabled", s.bubbleEnabled)
            .putBoolean("onlyWhenTyping", s.onlyWhenTyping)
            .putBoolean("haptics", s.haptics)
            .apply()
        _state.value = s
    }

    private fun read(): Settings {
        val replacements = runCatching {
            val arr = JSONArray(sp.getString("replacements", "[]"))
            (0 until arr.length()).map { arr.getJSONObject(it).let { o -> Replacement(o.getString("spoken"), o.getString("written")) } }
        }.getOrDefault(emptyList())
        return Settings(
            style = runCatching { FormatStyle.valueOf(sp.getString("style", null)!!) }.getOrDefault(FormatStyle.SMART),
            speechModel = sp.getString("speechModel", null) ?: Catalog.DEFAULT_SPEECH,
            formatterModel = sp.getString("formatterModel", null) ?: Catalog.DEFAULT_FORMATTER,
            language = sp.getString("language", null) ?: "en",
            vocabulary = parseVocabulary(sp.getString("vocabulary", "") ?: ""),
            replacements = replacements,
            bubbleEnabled = sp.getBoolean("bubbleEnabled", false),
            onlyWhenTyping = sp.getBoolean("onlyWhenTyping", true),
            haptics = sp.getBoolean("haptics", true),
        )
    }

    companion object {
        fun parseVocabulary(raw: String): List<String> =
            raw.split('\n', ',').map { it.trim() }.filter { it.isNotEmpty() }

        val languages = listOf(
            "auto" to "Auto-detect", "en" to "English", "fr" to "French", "es" to "Spanish",
            "de" to "German", "it" to "Italian", "pt" to "Portuguese", "nl" to "Dutch",
            "ja" to "Japanese", "zh" to "Chinese", "ko" to "Korean", "ar" to "Arabic", "hi" to "Hindi",
        )
    }
}
