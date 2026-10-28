#include "veltrio_llm.h"

#include <mach/mach.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ggml.h"
#include "ggml-backend.h"
#include "llama.h"

typedef struct vl_handle {
    struct llama_model *   model;
    struct llama_context * ctx;
    const struct llama_vocab * vocab;
    const char * chat_template; // owned by the model; may be NULL
    // Prompt tokens currently in the KV cache (prefix reuse across calls).
    llama_token * cached;
    int32_t n_cached;
} vl_handle;

static int vl_logging = 0;
static int vl_backend_ready = 0;

static void vl_log_cb(enum ggml_log_level level, const char * text, void * user_data) {
    (void) level;
    (void) user_data;
    if (vl_logging) {
        fputs(text, stderr);
    }
}

static void vl_set_err(char * err, int32_t err_len, const char * fmt, ...) {
    if (err == NULL || err_len <= 0) return;
    va_list args;
    va_start(args, fmt);
    vsnprintf(err, (size_t) err_len, fmt, args);
    va_end(args);
}

void vl_set_logging(int32_t enabled) {
    vl_logging = enabled != 0;
}

static void vl_footprint(int64_t * current, int64_t * peak) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    *current = -1;
    *peak = -1;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t) &info, &count) != KERN_SUCCESS) {
        return;
    }
    *current = (int64_t) info.phys_footprint;
    if (count >= TASK_VM_INFO_REV3_COUNT) {
        *peak = info.ledger_phys_footprint_peak;
    }
}

int64_t vl_memory_limit_remaining(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t) &info, &count) != KERN_SUCCESS ||
        count < TASK_VM_INFO_REV4_COUNT) {
        return -1;
    }
    return (int64_t) info.limit_bytes_remaining;
}

int64_t vl_memory_footprint(void) {
    int64_t current, peak;
    vl_footprint(&current, &peak);
    return current;
}

void * vl_load(const char * model_path, int32_t n_ctx, int32_t n_gpu_layers,
               int32_t n_threads, char * err, int32_t err_len) {
    if (!vl_backend_ready) {
        llama_log_set(vl_log_cb, NULL);
        llama_backend_init();
        ggml_time_init();
        vl_backend_ready = 1;
    }

    struct llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = n_gpu_layers;

    struct llama_model * model = llama_model_load_from_file(model_path, mparams);
    if (model == NULL) {
        vl_set_err(err, err_len, "failed to load model");
        return NULL;
    }

    struct llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx = (uint32_t) n_ctx;
    // The whole prompt is decoded in one batch; see the length check in vl_generate.
    cparams.n_batch = (uint32_t) n_ctx;
    cparams.n_threads = n_threads;
    cparams.n_threads_batch = n_threads;
    cparams.no_perf = 1;

    struct llama_context * ctx = llama_init_from_model(model, cparams);
    if (ctx == NULL) {
        llama_model_free(model);
        vl_set_err(err, err_len, "failed to create context (n_ctx=%d)", n_ctx);
        return NULL;
    }

    vl_handle * h = calloc(1, sizeof(vl_handle));
    if (h == NULL) {
        llama_free(ctx);
        llama_model_free(model);
        vl_set_err(err, err_len, "out of memory");
        return NULL;
    }
    h->model = model;
    h->ctx = ctx;
    h->vocab = llama_model_get_vocab(model);
    h->chat_template = llama_model_chat_template(model, NULL);
    return h;
}

// Formats the conversation with the model's own chat template.
// Returns a malloc'd string or NULL.
static char * vl_format_chat(const vl_handle * h, const char * system, const char * user) {
    struct llama_chat_message msgs[2];
    size_t n = 0;
    if (system != NULL && system[0] != '\0') {
        msgs[n].role = "system";
        msgs[n].content = system;
        n++;
    }
    msgs[n].role = "user";
    msgs[n].content = user;
    n++;

    int32_t cap = (int32_t) (strlen(user) + (system ? strlen(system) : 0)) * 2 + 512;
    char * buf = malloc((size_t) cap);
    if (buf == NULL) return NULL;
    int32_t len = llama_chat_apply_template(h->chat_template, msgs, n, 1, buf, cap);
    if (len > cap) {
        char * bigger = realloc(buf, (size_t) len + 1);
        if (bigger == NULL) {
            free(buf);
            return NULL;
        }
        buf = bigger;
        cap = len + 1;
        len = llama_chat_apply_template(h->chat_template, msgs, n, 1, buf, cap);
    }
    if (len < 0) {
        free(buf);
        return NULL;
    }
    if (len >= cap) {
        char * bigger = realloc(buf, (size_t) len + 1);
        if (bigger == NULL) {
            free(buf);
            return NULL;
        }
        buf = bigger;
    }
    buf[len] = '\0';
    return buf;
}

int32_t vl_generate(void * handle, const char * system, const char * user,
                    const char * grammar, int32_t max_tokens, float temperature,
                    uint32_t seed, char * out, int32_t out_len, vl_stats * stats,
                    char * err, int32_t err_len) {
    vl_handle * h = (vl_handle *) handle;
    if (h == NULL || user == NULL || out == NULL || out_len <= 0) {
        vl_set_err(err, err_len, "invalid arguments");
        return -1;
    }
    out[0] = '\0';
    if (stats != NULL) memset(stats, 0, sizeof(*stats));

    char * prompt = vl_format_chat(h, system, user);
    if (prompt == NULL) {
        vl_set_err(err, err_len, "chat template failed");
        return -1;
    }

    const int32_t n_ctx = (int32_t) llama_n_ctx(h->ctx);
    const int32_t prompt_len = (int32_t) strlen(prompt);
    int32_t n_prompt = -llama_tokenize(h->vocab, prompt, prompt_len, NULL, 0, 1, 1);
    if (n_prompt <= 0 || n_prompt + max_tokens > n_ctx) {
        free(prompt);
        vl_set_err(err, err_len, "prompt too long: %d tokens + %d max new > n_ctx %d",
                   n_prompt, max_tokens, n_ctx);
        return -1;
    }
    llama_token * tokens = malloc(sizeof(llama_token) * (size_t) n_prompt);
    if (tokens == NULL) {
        free(prompt);
        vl_set_err(err, err_len, "out of memory");
        return -1;
    }
    llama_tokenize(h->vocab, prompt, prompt_len, tokens, n_prompt, 1, 1);
    free(prompt);

    // The grammar is kept out of the chain: checking only the chosen token
    // against it is much cheaper than masking the whole vocabulary each step
    // (same approach as llama.cpp's common_sampler_sample).
    struct llama_sampler * grmr = NULL;
    if (grammar != NULL && grammar[0] != '\0') {
        grmr = llama_sampler_init_grammar(h->vocab, grammar, "root");
        if (grmr == NULL) {
            free(tokens);
            vl_set_err(err, err_len, "invalid grammar");
            return -1;
        }
    }
    struct llama_sampler * chain = llama_sampler_chain_init(llama_sampler_chain_default_params());
    if (temperature <= 0.0f) {
        llama_sampler_chain_add(chain, llama_sampler_init_greedy());
    } else {
        llama_sampler_chain_add(chain, llama_sampler_init_temp(temperature));
        llama_sampler_chain_add(chain, llama_sampler_init_dist(seed));
    }

    const int32_t n_vocab = llama_vocab_n_tokens(h->vocab);
    llama_token_data * cand = malloc(sizeof(llama_token_data) * (size_t) n_vocab);
    if (cand == NULL) {
        free(tokens);
        if (grmr) llama_sampler_free(grmr);
        llama_sampler_free(chain);
        vl_set_err(err, err_len, "out of memory");
        return -1;
    }

    // Reuse the KV cache for the prefix shared with the previous prompt. At
    // least one token is always decoded so fresh logits exist.
    llama_memory_t mem = llama_get_memory(h->ctx);
    int32_t n_keep = 0;
    while (n_keep < h->n_cached && n_keep < n_prompt && h->cached[n_keep] == tokens[n_keep]) {
        n_keep++;
    }
    if (n_keep == n_prompt) n_keep--;
    // Partial removal is unsupported by some caches (e.g. sliding-window
    // attention); fall back to a clean context.
    if (n_keep == 0 || !llama_memory_seq_rm(mem, 0, n_keep, -1)) {
        llama_memory_clear(mem, 1);
        n_keep = 0;
    }
    free(h->cached);
    h->cached = NULL;
    h->n_cached = 0;

    int32_t written = 0;
    int32_t generated = 0;
    int32_t rc = 0;
    int64_t sample_us = 0;

    const int64_t t0 = ggml_time_us();
    if (llama_decode(h->ctx, llama_batch_get_one(tokens + n_keep, n_prompt - n_keep)) != 0) {
        vl_set_err(err, err_len, "prompt decode failed");
        rc = -1;
    }
    // Decoding is asynchronous on Metal; wait so prompt time is not billed
    // to the first generated token.
    llama_synchronize(h->ctx);
    const int64_t t1 = ggml_time_us();

    char piece[256];
    while (rc == 0 && generated < max_tokens) {
        llama_synchronize(h->ctx);
        const int64_t ts = ggml_time_us();
        const float * logits = llama_get_logits_ith(h->ctx, -1);
        for (int32_t i = 0; i < n_vocab; i++) {
            cand[i] = (llama_token_data) { i, logits[i], 0.0f };
        }
        llama_token_data_array cur = { cand, (size_t) n_vocab, -1, false };
        llama_sampler_apply(chain, &cur);
        llama_token tok = cur.data[cur.selected].id;

        if (grmr != NULL) {
            llama_token_data single = { tok, 1.0f, 0.0f };
            llama_token_data_array one = { &single, 1, -1, false };
            llama_sampler_apply(grmr, &one);
            if (single.logit == -INFINITY) {
                for (int32_t i = 0; i < n_vocab; i++) {
                    cand[i] = (llama_token_data) { i, logits[i], 0.0f };
                }
                cur = (llama_token_data_array) { cand, (size_t) n_vocab, -1, false };
                llama_sampler_apply(grmr, &cur);
                llama_sampler_apply(chain, &cur);
                tok = cur.data[cur.selected].id;
            }
            llama_sampler_accept(grmr, tok);
        }
        llama_sampler_accept(chain, tok);
        sample_us += ggml_time_us() - ts;

        if (llama_vocab_is_eog(h->vocab, tok)) break;
        generated++;

        int32_t n = llama_token_to_piece(h->vocab, tok, piece, (int32_t) sizeof(piece), 0, 0);
        if (n < 0) {
            vl_set_err(err, err_len, "token decode failed");
            rc = -1;
            break;
        }
        if (written + n >= out_len) {
            vl_set_err(err, err_len, "output buffer too small (%d bytes)", out_len);
            rc = -1;
            break;
        }
        memcpy(out + written, piece, (size_t) n);
        written += n;
        out[written] = '\0';

        if (llama_decode(h->ctx, llama_batch_get_one(&tok, 1)) != 0) {
            vl_set_err(err, err_len, "decode failed after %d tokens", generated);
            rc = -1;
        }
    }
    llama_synchronize(h->ctx);
    const int64_t t2 = ggml_time_us();

    free(cand);
    if (grmr) llama_sampler_free(grmr);
    llama_sampler_free(chain);
    if (rc == 0) {
        // Keep the prompt tokens for the next call; generated tokens beyond
        // them are dropped by the seq_rm above.
        h->cached = tokens;
        h->n_cached = n_prompt;
    } else {
        free(tokens);
    }

    if (stats != NULL) {
        stats->prompt_tokens = n_prompt;
        stats->generated_tokens = generated;
        stats->cached_tokens = n_keep;
        stats->prompt_ms = (double) (t1 - t0) / 1000.0;
        stats->generation_ms = (double) (t2 - t1) / 1000.0;
        stats->sample_ms = (double) sample_us / 1000.0;
        vl_footprint(&stats->footprint_bytes, &stats->peak_footprint_bytes);
    }
    return rc == 0 ? written : -1;
}

void vl_free(void * handle) {
    vl_handle * h = (vl_handle *) handle;
    if (h == NULL) return;
    llama_free(h->ctx);
    llama_model_free(h->model);
    free(h->cached);
    free(h);
}

int32_t vl_backend_info(char * buf, int32_t buf_len) {
    if (!vl_backend_ready) {
        llama_log_set(vl_log_cb, NULL);
        llama_backend_init();
        ggml_time_init();
        vl_backend_ready = 1;
    }
    const size_t n = ggml_backend_dev_count();
    int32_t used = 0;
    if (buf != NULL && buf_len > 0) buf[0] = '\0';
    for (size_t i = 0; i < n && buf != NULL && used < buf_len; i++) {
        used += snprintf(buf + used, (size_t) (buf_len - used), "%s%s",
                         i == 0 ? "" : ", ", ggml_backend_dev_name(ggml_backend_dev_get(i)));
    }
    return (int32_t) n;
}
