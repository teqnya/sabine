// Thin C wrapper over llama.cpp for Dart FFI.
//
// Keeps the FFI surface small and stable: plain pointers and scalars only,
// no llama.cpp structs cross the boundary. One handle = one model + context.
// Calls on the same handle must not run concurrently.

#ifndef VELTRIO_LLM_H
#define VELTRIO_LLM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct vl_stats {
    int32_t prompt_tokens;
    int32_t generated_tokens;
    // Leading prompt tokens reused from the previous call's KV cache.
    int32_t cached_tokens;
    double  prompt_ms;
    double  generation_ms;
    // Part of generation_ms spent choosing tokens (incl. grammar checks).
    double  sample_ms;
    // Process memory footprint (bytes) after generation, and its high-water mark.
    int64_t footprint_bytes;
    int64_t peak_footprint_bytes;
} vl_stats;

// Enables llama.cpp logging to stderr. Off by default: logs must never carry
// message content (CLAUDE.md §8).
void vl_set_logging(int32_t enabled);

// Returns NULL on failure and writes a message to err.
void * vl_load(const char * model_path, int32_t n_ctx, int32_t n_gpu_layers,
               int32_t n_threads, char * err, int32_t err_len);

// Runs one chat completion. The KV cache of the longest prompt prefix shared
// with the previous call is reused (e.g. fixed instructions), so only the new
// tail is decoded; results are the same as from a clean context. system may be NULL.
// grammar is a GBNF string with a `root` rule, or NULL for free text.
// temperature <= 0 means greedy decoding.
// Returns the number of bytes written to out (excluding the NUL terminator),
// or -1 on failure with a message in err.
int32_t vl_generate(void * handle, const char * system, const char * user,
                    const char * grammar, int32_t max_tokens, float temperature,
                    uint32_t seed, char * out, int32_t out_len, vl_stats * stats,
                    char * err, int32_t err_len);

void vl_free(void * handle);

// Writes a comma-separated list of available compute devices (e.g. "MTL0, CPU")
// to buf. Returns the number of devices.
int32_t vl_backend_info(char * buf, int32_t buf_len);

// Current process memory footprint in bytes (what iOS uses for jetsam limits).
int64_t vl_memory_footprint(void);

// Bytes left before iOS terminates the app for memory (jetsam), or -1 if the
// OS does not report it (e.g. macOS without a limit).
int64_t vl_memory_limit_remaining(void);

#ifdef __cplusplus
}
#endif

#endif
