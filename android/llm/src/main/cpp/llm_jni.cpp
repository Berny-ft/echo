#include <jni.h>
#include <android/log.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <string>
#include <vector>
#include "llama.h"

#define LOG_TAG "EchoLLM"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

namespace {

struct Session {
    llama_model *model = nullptr;
    llama_context *ctx = nullptr;
    const llama_vocab *vocab = nullptr;
    llama_sampler *sampler = nullptr;
    std::string tmpl;
    // Tokens currently held in the KV cache, so a repeated prefix (the instructions) is never re-processed.
    std::vector<llama_token> cached;
    std::atomic<bool> cancel{false};
};

void quiet_log(ggml_log_level level, const char *text, void *) {
    if (level >= GGML_LOG_LEVEL_WARN) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, "%s", text);
}

std::string jstr(JNIEnv *env, jstring s) {
    const char *c = env->GetStringUTFChars(s, nullptr);
    std::string out(c);
    env->ReleaseStringUTFChars(s, c);
    return out;
}

std::string apply_template(Session *s, const std::string &system, const std::string &user, bool add_assistant) {
    llama_chat_message msgs[2] = {{"system", system.c_str()}, {"user", user.c_str()}};
    const char *tmpl = s->tmpl.empty() ? nullptr : s->tmpl.c_str();
    std::vector<char> buf(system.size() + user.size() + 1024);
    int n = llama_chat_apply_template(tmpl, msgs, 2, add_assistant, buf.data(), (int) buf.size());
    if (n > (int) buf.size()) {
        buf.resize(n);
        n = llama_chat_apply_template(tmpl, msgs, 2, add_assistant, buf.data(), (int) buf.size());
    }
    return n < 0 ? system + "\n\n" + user + "\n\n" : std::string(buf.data(), n);
}

std::vector<llama_token> tokenize(Session *s, const std::string &text) {
    int n = -llama_tokenize(s->vocab, text.c_str(), (int) text.size(), nullptr, 0, true, true);
    std::vector<llama_token> toks(n);
    llama_tokenize(s->vocab, text.c_str(), (int) text.size(), toks.data(), n, true, true);
    return toks;
}

/// Makes the KV cache hold exactly `toks`, reusing the longest prefix already there.
/// Returns false on decode failure. Leaves the logits of the last token ready for sampling.
bool feed(Session *s, const std::vector<llama_token> &toks) {
    size_t keep = 0;
    while (keep < s->cached.size() && keep < toks.size() && s->cached[keep] == toks[keep]) ++keep;
    // Always re-decode at least the last token so fresh logits are available.
    if (keep == toks.size() && keep > 0) --keep;

    llama_memory_seq_rm(llama_get_memory(s->ctx), 0, (llama_pos) keep, -1);
    s->cached.resize(keep);

    const int n_batch = (int) llama_n_batch(s->ctx);
    for (size_t i = keep; i < toks.size(); i += n_batch) {
        int n = (int) std::min<size_t>(n_batch, toks.size() - i);
        llama_batch batch = llama_batch_get_one(const_cast<llama_token *>(toks.data() + i), n);
        if (llama_decode(s->ctx, batch) != 0) {
            s->cached.clear();
            llama_memory_clear(llama_get_memory(s->ctx), true);
            return false;
        }
        s->cached.insert(s->cached.end(), toks.begin() + (long) i, toks.begin() + (long) i + n);
    }
    return true;
}

}  // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_com_echo_llm_LlmSession_nativeLoad(JNIEnv *env, jclass, jstring jpath, jint threads, jint n_ctx) {
    llama_log_set(quiet_log, nullptr);
    llama_backend_init();

    std::string path = jstr(env, jpath);
    llama_model_params mp = llama_model_default_params();
    mp.n_gpu_layers = 0;
    llama_model *model = llama_model_load_from_file(path.c_str(), mp);
    if (!model) return 0;

    llama_context_params cp = llama_context_default_params();
    cp.n_ctx = n_ctx;
    cp.n_batch = 512;
    cp.n_ubatch = 512;
    cp.n_threads = threads;
    cp.n_threads_batch = threads;
    llama_context *ctx = llama_init_from_model(model, cp);
    if (!ctx) {
        llama_model_free(model);
        return 0;
    }

    auto *s = new Session();
    s->model = model;
    s->ctx = ctx;
    s->vocab = llama_model_get_vocab(model);
    if (const char *t = llama_model_chat_template(model, nullptr)) s->tmpl = t;

    auto sp = llama_sampler_chain_default_params();
    s->sampler = llama_sampler_chain_init(sp);
    llama_sampler_chain_add(s->sampler, llama_sampler_init_penalties(llama_vocab_n_tokens(s->vocab), 64, 1.1f, 0.0f, 0.0f));
    llama_sampler_chain_add(s->sampler, llama_sampler_init_greedy());
    return reinterpret_cast<jlong>(s);
}

extern "C" JNIEXPORT void JNICALL
Java_com_echo_llm_LlmSession_nativeFree(JNIEnv *, jclass, jlong ptr) {
    auto *s = reinterpret_cast<Session *>(ptr);
    if (!s) return;
    llama_sampler_free(s->sampler);
    llama_free(s->ctx);
    llama_model_free(s->model);
    delete s;
}

extern "C" JNIEXPORT void JNICALL
Java_com_echo_llm_LlmSession_nativeCancel(JNIEnv *, jclass, jlong ptr) {
    if (auto *s = reinterpret_cast<Session *>(ptr)) s->cancel = true;
}

/// Processes the instructions ahead of time (while the user is still talking), so formatting
/// only has to read the transcript itself.
extern "C" JNIEXPORT void JNICALL
Java_com_echo_llm_LlmSession_nativePrewarm(JNIEnv *env, jclass, jlong ptr, jstring jsystem) {
    auto *s = reinterpret_cast<Session *>(ptr);
    if (!s) return;
    const std::string marker = "\x01\x02";
    std::string full = apply_template(s, jstr(env, jsystem), marker, false);
    size_t at = full.find(marker);
    if (at == std::string::npos) return;
    const auto t0 = std::chrono::steady_clock::now();
    feed(s, tokenize(s, full.substr(0, at)));
    LOGI("prewarmed %zu tokens in %lld ms", s->cached.size(),
         (long long) std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count());
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_echo_llm_LlmSession_nativeGenerate(JNIEnv *env, jclass, jlong ptr, jstring jsystem, jstring juser, jint max_tokens) {
    auto *s = reinterpret_cast<Session *>(ptr);
    if (!s) return nullptr;
    s->cancel = false;

    const auto t0 = std::chrono::steady_clock::now();
    std::vector<llama_token> prompt = tokenize(s, apply_template(s, jstr(env, jsystem), jstr(env, juser), true));
    if ((int) prompt.size() + max_tokens > (int) llama_n_ctx(s->ctx)) return nullptr;
    if (!feed(s, prompt)) return nullptr;
    const auto t1 = std::chrono::steady_clock::now();

    llama_sampler_reset(s->sampler);
    std::string out;
    int produced = 0;
    char piece[256];
    while (produced < max_tokens && !s->cancel) {
        llama_token tok = llama_sampler_sample(s->sampler, s->ctx, -1);
        if (llama_vocab_is_eog(s->vocab, tok)) break;
        int n = llama_token_to_piece(s->vocab, tok, piece, sizeof(piece), 0, false);
        if (n > 0) out.append(piece, n);
        ++produced;
        llama_batch batch = llama_batch_get_one(&tok, 1);
        if (llama_decode(s->ctx, batch) != 0) break;
        s->cached.push_back(tok);
    }
    const auto t2 = std::chrono::steady_clock::now();
    LOGI("prompt %zu tok in %lld ms, generated %d tok in %lld ms", prompt.size(),
         (long long) std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count(), produced,
         (long long) std::chrono::duration_cast<std::chrono::milliseconds>(t2 - t1).count());
    if (s->cancel) return nullptr;
    return env->NewStringUTF(out.c_str());
}
