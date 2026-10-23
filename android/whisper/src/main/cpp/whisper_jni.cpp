#include <jni.h>
#include <android/log.h>
#include <string>
#include <thread>
#include <chrono>
#include <algorithm>
#include "whisper.h"

#define LOG_TAG "EchoWhisper"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

static void quiet_log(ggml_log_level level, const char *text, void *) {
    if (level >= GGML_LOG_LEVEL_WARN) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, "%s", text);
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_echo_whisper_WhisperContext_nativeInit(JNIEnv *env, jclass, jstring jpath) {
    whisper_log_set(quiet_log, nullptr);
    const char *path = env->GetStringUTFChars(jpath, nullptr);
    whisper_context_params params = whisper_context_default_params();
    params.use_gpu = false;
    params.flash_attn = true;
    whisper_context *ctx = whisper_init_from_file_with_params(path, params);
    env->ReleaseStringUTFChars(jpath, path);
    return reinterpret_cast<jlong>(ctx);
}

extern "C" JNIEXPORT void JNICALL
Java_com_echo_whisper_WhisperContext_nativeFree(JNIEnv *, jclass, jlong ptr) {
    if (ptr) whisper_free(reinterpret_cast<whisper_context *>(ptr));
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_echo_whisper_WhisperContext_nativeTranscribe(JNIEnv *env, jclass, jlong ptr, jfloatArray jsamples,
                                                      jstring jlang, jstring jprompt, jint threads) {
    auto *ctx = reinterpret_cast<whisper_context *>(ptr);
    if (!ctx) return env->NewStringUTF("");

    const char *lang = env->GetStringUTFChars(jlang, nullptr);
    const char *prompt = env->GetStringUTFChars(jprompt, nullptr);
    jsize n = env->GetArrayLength(jsamples);
    jfloat *samples = env->GetFloatArrayElements(jsamples, nullptr);

    whisper_full_params p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    p.n_threads = threads;
    p.language = lang;
    p.detect_language = std::string(lang) == "auto";
    p.translate = false;
    p.no_timestamps = true;
    p.print_progress = false;
    p.print_realtime = false;
    p.print_special = false;
    p.print_timestamps = false;
    p.suppress_blank = true;
    p.suppress_nst = true;
    p.temperature_inc = 0.0f;  // no fallback re-decoding: faster, and dictation audio is clean
    p.initial_prompt = prompt[0] ? prompt : nullptr;
    // Short clips: don't let whisper pad a 3 s utterance to a full 30 s window more than needed.
    p.audio_ctx = 0;

    const auto t0 = std::chrono::steady_clock::now();
    int rc = whisper_full(ctx, p, samples, n);
    const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count();

    std::string out;
    if (rc == 0) {
        const int segs = whisper_full_n_segments(ctx);
        for (int i = 0; i < segs; ++i) out += whisper_full_get_segment_text(ctx, i);
    }
    LOGI("transcribed %.1f s of audio in %lld ms (rc=%d)", n / 16000.0, (long long) ms, rc);

    env->ReleaseFloatArrayElements(jsamples, samples, JNI_ABORT);
    env->ReleaseStringUTFChars(jlang, lang);
    env->ReleaseStringUTFChars(jprompt, prompt);
    return env->NewStringUTF(out.c_str());
}
