package com.echo.dictation

import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentCallbacks2
import com.echo.dictation.engine.DictationController
import com.echo.dictation.engine.Formatter
import com.echo.dictation.engine.Transcriber
import com.echo.dictation.model.HistoryStore
import com.echo.dictation.model.ModelStore
import com.echo.dictation.model.Prefs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class EchoApp : Application() {
    lateinit var prefs: Prefs; private set
    lateinit var models: ModelStore; private set
    lateinit var history: HistoryStore; private set
    val transcriber = Transcriber()
    val formatter = Formatter()
    lateinit var dictation: DictationController; private set
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onCreate() {
        super.onCreate()
        instance = this
        prefs = Prefs(this)
        models = ModelStore(this)
        history = HistoryStore(this)
        dictation = DictationController(this)
    }

    fun copyToClipboard(text: String) {
        getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("Echo", text))
    }

    /** The formatting model is ~1 GB; give it back when Android is short on memory and we're idle. */
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= ComponentCallbacks2.TRIM_MEMORY_BACKGROUND && !dictation.isBusy) {
            scope.launch { formatter.unload() }
        }
    }

    companion object {
        lateinit var instance: EchoApp; private set
    }
}
