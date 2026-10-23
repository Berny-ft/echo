package com.echo.dictation.model

enum class ModelKind { SPEECH, FORMATTER }

data class ModelInfo(
    val id: String,
    val kind: ModelKind,
    val title: String,
    val detail: String,
    val url: String,
    val bytes: Long,
    /** English-only speech models can't transcribe other languages. */
    val englishOnly: Boolean = false,
) {
    val fileName: String get() = url.substringAfterLast('/')
    val sizeLabel: String get() = if (bytes >= 1_000_000_000) "%.1f GB".format(bytes / 1e9) else "${bytes / 1_000_000} MB"
}

object Catalog {
    const val FORMATTER_OFF = "off"
    const val DEFAULT_SPEECH = "small.en"
    const val DEFAULT_FORMATTER = FORMATTER_OFF

    private const val WHISPER = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

    val speech = listOf(
        ModelInfo("small.en", ModelKind.SPEECH, "Small (English)", "Accurate, about 2–4 s per sentence on a Pixel 7",
            "$WHISPER/ggml-small.en-q5_1.bin", 190_098_681, englishOnly = true),
        ModelInfo("base.en", ModelKind.SPEECH, "Base (English)", "Fastest, about 1 s, more mistakes",
            "$WHISPER/ggml-base.en-q5_1.bin", 59_721_011, englishOnly = true),
        ModelInfo("small", ModelKind.SPEECH, "Small (multilingual)", "For languages other than English",
            "$WHISPER/ggml-small-q5_1.bin", 190_085_487),
        ModelInfo("large-v3-turbo", ModelKind.SPEECH, "Large v3 Turbo", "Best accuracy, all languages. Slow on a Pixel 7",
            "$WHISPER/ggml-large-v3-turbo-q5_0.bin", 574_041_195),
    )

    val formatters = listOf(
        ModelInfo("qwen2.5-1.5b", ModelKind.FORMATTER, "Qwen 2.5 1.5B", "Best formatting. A few seconds per dictation",
            "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf", 1_117_320_736),
        ModelInfo("qwen2.5-0.5b", ModelKind.FORMATTER, "Qwen 2.5 0.5B", "Faster, but follows instructions less reliably",
            "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf", 491_400_032),
    )

    val all = speech + formatters
    fun find(id: String): ModelInfo? = all.firstOrNull { it.id == id }
}
