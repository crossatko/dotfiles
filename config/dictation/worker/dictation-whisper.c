// dictation-whisper: keeps whisper.cpp models resident and answers recognition requests over stdin/stdout.
//
// Started by the dictation service (config/dictation/lib/dictation/whisper.py), never by hand except for debugging.
//
//   dictation-whisper --model live=PATH --model final=PATH [--no-gpu] [--gpu-device N] [--threads N] [--verbose]
//   dictation-whisper --list-devices
//
// --gpu-device N picks the N-th GPU (0 = the first, the default; the order --list-devices prints). An index that does
// not exist is the same GPU error as a failed Vulkan init (never another device or the CPU). --list-devices prints one
// JSON line per GPU {"index":N,"name":"...","type":"discrete"|"integrated","free_mb":N,"total_mb":N} and exits 0
// (no GPU backend = no lines); a worker that predates it answers {"error":"unknown argument"} and exits 2.
//
// Startup: every model is loaded, then one JSON line is printed: {"ready":true,"slots":["live","final"],"detect":true,"load_ms":N}
// ("detect":true announces the "detect" request below; a worker without it has no language detection)
// (or {"error":"..."} and exit 2). Without --no-gpu a missing or unusable GPU backend (Vulkan init failed) is an error
// {"error":"...","code":"gpu"} and exit 4: whisper.cpp would otherwise fall back to the CPU without a word, which is
// minutes per pass instead of a fraction of a second. Memory goes back to the system when the process exits (the
// service unloads by stopping the worker).
// Request (stdin): one text line "ID SLOT LANG TRANSLATE BEAM NSAMPLES\n" followed by NSAMPLES little-endian float32
// samples, 16 kHz mono. LANG is a whisper language code (never "auto": the caller pins it, after a "detect" request in auto mode). TRANSLATE is 0/1,
// BEAM is 0 for greedy decoding or the beam size.
// LANG "detect" instead runs language detection on the audio (TRANSLATE and BEAM ignored) and replies
// {"id":ID,"ms":N,"probs":{"<code>":P,...}} for every language. An optional seventh field PROMPTBYTES (0..1024) means that many
// UTF-8 bytes follow the samples: the initial prompt (the cleanup stage's vocabulary hints, off by default).
// Reply (stdout): one JSON line {"id":ID,"ms":N,"segments":[{"t0":MS,"t1":MS,"text":"..."}]} or {"id":ID,"error":"..."}.
// No shortened audio context is used on purpose (it made results worse in the benchmark); a prompt only when sent.
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "ggml-backend.h"
#include "whisper.h"

#define MAX_SLOTS 4
#define MAX_SAMPLES (16000 * 60 * 10)  // ten minutes, a hard upper bound for one request

struct slot {
    char name[32];
    struct whisper_context *ctx;
};

static int verbose = 0;

static void log_cb(enum ggml_log_level level, const char *text, void *user) {
    (void)level;
    (void)user;
    if (verbose) fputs(text, stderr);
}

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

static void json_str(FILE *out, const char *s) {
    fputc('"', out);
    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        switch (*p) {
        case '"': fputs("\\\"", out); break;
        case '\\': fputs("\\\\", out); break;
        case '\n': fputs("\\n", out); break;
        case '\r': fputs("\\r", out); break;
        case '\t': fputs("\\t", out); break;
        default:
            if (*p < 0x20) fprintf(out, "\\u%04x", *p);
            else fputc(*p, out);
        }
    }
    fputc('"', out);
}

// GPUs in the order whisper.cpp's gpu_device indexes them: devices of type GPU or IGPU, counted in backend order.
static int gpu_count(void) {
    int n = 0;
    for (size_t i = 0; i < ggml_backend_dev_count(); i++) {
        enum ggml_backend_dev_type t = ggml_backend_dev_type(ggml_backend_dev_get(i));
        if (t == GGML_BACKEND_DEVICE_TYPE_GPU || t == GGML_BACKEND_DEVICE_TYPE_IGPU) n++;
    }
    return n;
}

static int list_devices(void) {
    whisper_log_set(log_cb, NULL);
    ggml_backend_load_all();
    int index = 0;
    for (size_t i = 0; i < ggml_backend_dev_count(); i++) {
        ggml_backend_dev_t dev = ggml_backend_dev_get(i);
        enum ggml_backend_dev_type t = ggml_backend_dev_type(dev);
        if (t != GGML_BACKEND_DEVICE_TYPE_GPU && t != GGML_BACKEND_DEVICE_TYPE_IGPU) continue;
        size_t free_b = 0, total_b = 0;
        ggml_backend_dev_memory(dev, &free_b, &total_b);
        printf("{\"index\":%d,\"name\":", index++);
        json_str(stdout, ggml_backend_dev_description(dev));
        printf(",\"type\":\"%s\",\"free_mb\":%zu,\"total_mb\":%zu}\n",
               t == GGML_BACKEND_DEVICE_TYPE_IGPU ? "integrated" : "discrete", free_b >> 20, total_b >> 20);
    }
    fflush(stdout);
    return 0;
}

static void reply_error(const char *id, const char *msg) {
    printf("{\"id\":");
    json_str(stdout, id);
    printf(",\"error\":");
    json_str(stdout, msg);
    printf("}\n");
    fflush(stdout);
}

int main(int argc, char **argv) {
    struct slot slots[MAX_SLOTS];
    const char *paths[MAX_SLOTS];
    int n_slots = 0, use_gpu = 1, threads = 4, gpu_device = 0;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--model") && i + 1 < argc) {
            const char *arg = argv[++i];
            const char *eq = strchr(arg, '=');
            if (!eq || eq == arg || (size_t)(eq - arg) >= sizeof slots[0].name || n_slots == MAX_SLOTS) {
                printf("{\"error\":\"bad --model argument, want NAME=PATH\"}\n");
                return 2;
            }
            memcpy(slots[n_slots].name, arg, eq - arg);
            slots[n_slots].name[eq - arg] = 0;
            paths[n_slots++] = eq + 1;
        } else if (!strcmp(argv[i], "--no-gpu")) {
            use_gpu = 0;
        } else if (!strcmp(argv[i], "--list-devices")) {
            return list_devices();
        } else if (!strcmp(argv[i], "--gpu-device") && i + 1 < argc) {
            char *end = NULL;
            long d = strtol(argv[++i], &end, 10);
            if (!*argv[i] || *end || d < 0 || d > 1000) {
                printf("{\"error\":\"bad --gpu-device argument, want an index 0 or more\",\"code\":\"gpu\"}\n");
                return 4;
            }
            gpu_device = (int)d;
        } else if (!strcmp(argv[i], "--threads") && i + 1 < argc) {
            threads = atoi(argv[++i]);
            if (threads < 1) threads = 1;
        } else if (!strcmp(argv[i], "--verbose")) {
            verbose = 1;
        } else {
            printf("{\"error\":\"unknown argument\"}\n");
            return 2;
        }
    }
    if (n_slots == 0) {
        printf("{\"error\":\"no --model given\"}\n");
        return 2;
    }

    whisper_log_set(log_cb, NULL);
    if (use_gpu) {
        ggml_backend_load_all();
        int gpus = gpu_count();
        if (!gpus) {
            printf("{\"error\":\"no GPU backend available (Vulkan initialisation failed)\",\"code\":\"gpu\"}\n");
            return 4;
        }
        if (gpu_device >= gpus) {
            char msg[200];
            snprintf(msg, sizeof msg, "GPU device %d does not exist (%d found)", gpu_device, gpus);
            printf("{\"error\":");
            json_str(stdout, msg);
            printf(",\"code\":\"gpu\"}\n");
            return 4;
        }
    }
    double t_load = now_ms();
    for (int i = 0; i < n_slots; i++) {
        struct whisper_context_params cp = whisper_context_default_params();
        cp.use_gpu = use_gpu;
        cp.gpu_device = gpu_device;
        slots[i].ctx = whisper_init_from_file_with_params(paths[i], cp);
        if (!slots[i].ctx) {
            printf("{\"error\":");
            char msg[600];
            snprintf(msg, sizeof msg, "cannot load model %s: %s", slots[i].name, paths[i]);
            json_str(stdout, msg);
            printf("}\n");
            return 2;
        }
    }
    printf("{\"ready\":true,\"slots\":[");
    for (int i = 0; i < n_slots; i++) {
        if (i) putchar(',');
        json_str(stdout, slots[i].name);
    }
    printf("],\"detect\":true,\"load_ms\":%.0f}\n", now_ms() - t_load);
    fflush(stdout);

    char line[256];
    float *pcm = NULL;
    size_t pcm_cap = 0;
    while (fgets(line, sizeof line, stdin)) {
        char id[64], slot_name[32], lang[16];
        int translate = 0, beam = 0;
        long n = 0, prompt_len = 0;
        int fields = sscanf(line, "%63s %31s %15s %d %d %ld %ld", id, slot_name, lang, &translate, &beam, &n, &prompt_len);
        if (fields < 6 || n < 0 || n > MAX_SAMPLES || prompt_len < 0 || prompt_len > 1024) {
            // The stream is out of sync: there is no way to know how many sample bytes follow.
            reply_error("?", "bad request header");
            return 3;
        }
        if ((size_t)n > pcm_cap) {
            float *grown = realloc(pcm, (size_t)n * sizeof(float));
            if (!grown) {
                reply_error(id, "out of memory");
                return 3;
            }
            pcm = grown;
            pcm_cap = (size_t)n;
        }
        if (n && fread(pcm, sizeof(float), (size_t)n, stdin) != (size_t)n) break;
        char prompt[1025];
        if (prompt_len && fread(prompt, 1, (size_t)prompt_len, stdin) != (size_t)prompt_len) break;
        prompt[prompt_len] = 0;

        struct whisper_context *ctx = NULL;
        for (int i = 0; i < n_slots; i++)
            if (!strcmp(slots[i].name, slot_name)) ctx = slots[i].ctx;
        if (!ctx) {
            reply_error(id, "unknown model slot");
            continue;
        }
        if (n < 1600) {  // under 0.1 s: nothing to recognise, and whisper rejects very short input
            printf("{\"id\":");
            json_str(stdout, id);
            printf(",\"ms\":0,\"segments\":[]}\n");
            fflush(stdout);
            continue;
        }

        if (!strcmp(lang, "detect")) {
            // language detection on the first 30 s of the audio: {"id":ID,"ms":N,"probs":{"cs":0.93,...}}
            double td = now_ms();
            int n_lang = whisper_lang_max_id() + 1;
            float *probs = calloc((size_t)n_lang, sizeof(float));
            if (!probs) {
                reply_error(id, "out of memory");
                return 3;
            }
            if (whisper_pcm_to_mel(ctx, pcm, (int)n, threads) != 0 || whisper_lang_auto_detect(ctx, 0, threads, probs) < 0) {
                free(probs);
                reply_error(id, "language detection failed");
                continue;
            }
            printf("{\"id\":");
            json_str(stdout, id);
            printf(",\"ms\":%.0f,\"probs\":{", now_ms() - td);
            for (int i = 0; i < n_lang; i++) {
                if (i) putchar(',');
                json_str(stdout, whisper_lang_str(i));
                printf(":%.5f", probs[i]);
            }
            printf("}}\n");
            fflush(stdout);
            free(probs);
            continue;
        }

        struct whisper_full_params p =
            whisper_full_default_params(beam > 0 ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY);
        p.n_threads = threads;
        p.language = lang;
        p.detect_language = false;
        p.translate = translate != 0;
        p.no_context = true;
        p.single_segment = false;
        p.print_progress = false;
        p.print_realtime = false;
        p.print_special = false;
        p.print_timestamps = false;
        p.suppress_blank = true;
        p.suppress_nst = true;
        if (prompt_len) p.initial_prompt = prompt;
        if (beam > 0) {
            p.beam_search.beam_size = beam;
        } else {
            // Live passes: one greedy decode, no temperature fallback (a fallback can triple the pass time).
            p.greedy.best_of = 1;
            p.temperature_inc = 0.0f;
        }

        double t0 = now_ms();
        if (whisper_full(ctx, p, pcm, (int)n) != 0) {
            reply_error(id, "whisper_full failed");
            continue;
        }
        double ms = now_ms() - t0;
        printf("{\"id\":");
        json_str(stdout, id);
        printf(",\"ms\":%.0f,\"segments\":[", ms);
        int ns = whisper_full_n_segments(ctx);
        for (int i = 0; i < ns; i++) {
            if (i) putchar(',');
            // whisper timestamps are in units of 10 ms
            printf("{\"t0\":%lld,\"t1\":%lld,\"text\":", (long long)whisper_full_get_segment_t0(ctx, i) * 10,
                   (long long)whisper_full_get_segment_t1(ctx, i) * 10);
            json_str(stdout, whisper_full_get_segment_text(ctx, i));
            putchar('}');
        }
        printf("]}\n");
        fflush(stdout);
    }
    for (int i = 0; i < n_slots; i++) whisper_free(slots[i].ctx);
    free(pcm);
    return 0;
}
