/*
 * Startup shim for the Textura Cangjie/SDL host on HarmonyOS.
 *
 * Adapted from PixCap-Cangjie entry/src/main/cpp/host_bootstrap.c (read-only reference,
 * docs/scope/evidence/M0-host-chain.md). Changes: the host library name and the diagnostic symbol
 * are Textura's; the comment block is re-stated for this project. No logic was changed, because the
 * startup ordering below is the part that was proven on device.
 *
 * SDL's HarmonyOS startup dlopen()s "libmain.so" and dlsym()s SDL_AppInit from it. The real host is
 * libtextura_host.so, a Cangjie library built by cjpm (cangjie/harmony/host).
 *
 * A Cangjie shared library does NOT bring its own runtime up when it is dlopen()ed: the runtime has
 * to be started on a thread bound to the host ArkVM, and only the ArkTS-side loader can do that.
 * EntryAbility.onCreate calls requireCJLib("libtextura_host.so"), which registers the ArkVM, starts
 * the runtime, then opens the host library against the live runtime. The opposite order — bare
 * CJ_MRT_CjRuntimeInit/Start from this constructor — raised SIGBUS inside CJ_MRT_CjRuntimeStart on
 * the reference project, because runtime start rebuilds the calling thread's stack and that thread
 * belongs to ArkTS.
 *
 * So this shim does no runtime work at all: it only forwards SDL's entry points into the host
 * library. It is plain C with no Cangjie runtime dependency, which is what makes it safe to load
 * before (and independently of) the runtime.
 */
#include <dlfcn.h>
#include <stddef.h>

#define TEXTURA_HOST_LIB "libtextura_host.so"

static void *g_host = NULL;

/*
 * The Cangjie host is normally already resident (the ArkTS loader opened it). If it is not —
 * e.g. requireCJLib failed — this dlopen returns NULL and every forwarder below degrades to a
 * failure code, which SDL surfaces instead of faulting.
 */
static void *host_library(void)
{
    if (!g_host) {
        /* RTLD_GLOBAL so the library's dependencies resolve in the same namespace. */
        g_host = dlopen(TEXTURA_HOST_LIB, RTLD_NOW | RTLD_GLOBAL);
    }
    return g_host;
}

static void *host_symbol(const char *name)
{
    return g_host ? dlsym(g_host, name) : NULL;
}

/*
 * Diagnostics go through SDL_Log when it is reachable, because SDL routes it to hilog and Cangjie's
 * own println() does not show up there — a failure inside the Cangjie entry point would otherwise be
 * swallowed silently.
 */
static void diag(const char *what, const char *detail)
{
    typedef void (*log_fn)(const char *, ...);
    log_fn log = (log_fn)dlsym(RTLD_DEFAULT, "SDL_Log");
    if (log) {
        log("[textura-shim] %s: %s", what, detail ? detail : "(no detail)");
    }
}

int SDL_AppInit(void *appstate, int argc, char *argv[])
{
    typedef int (*fn_t)(void *, int, char **);
    fn_t fn = (fn_t)0;
    if (!host_library()) {
        diag("dlopen " TEXTURA_HOST_LIB " failed", dlerror());
        return 2; /* SDL_APP_FAILURE */
    }
    fn = (fn_t)host_symbol("SDL_AppInit");
    if (!fn) {
        diag("dlsym SDL_AppInit failed", dlerror());
        return 2;
    }
    {
        int rc = fn(appstate, argc, argv);
        if (rc != 0) {
            /* The Cangjie side parks its failure reason in a buffer we can read, because its own
             * println() does not reach hilog. */
            typedef const char *(*err_fn)(void);
            err_fn err = (err_fn)host_symbol("textura_host_error");
            const char *msg = err ? err() : NULL;
            diag("host SDL_AppInit failed", (msg && msg[0]) ? msg : "no reason reported");
        }
        return rc;
    }
}

int SDL_AppIterate(void *appstate)
{
    typedef int (*fn_t)(void *);
    fn_t fn = (fn_t)host_symbol("SDL_AppIterate");
    return fn ? fn(appstate) : 2;
}

int SDL_AppEvent(void *appstate, void *event)
{
    typedef int (*fn_t)(void *, void *);
    fn_t fn = (fn_t)host_symbol("SDL_AppEvent");
    /* CUI polls the SDL queue itself, so a missing forwarder must not fail the app. */
    return fn ? fn(appstate, event) : 0 /* SDL_APP_CONTINUE */;
}

void SDL_AppQuit(void *appstate, int result)
{
    typedef void (*fn_t)(void *, int);
    fn_t fn = (fn_t)host_symbol("SDL_AppQuit");
    if (fn) {
        fn(appstate, result);
    }
}
