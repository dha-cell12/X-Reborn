#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <sys/types.h>
#include <pwd.h>
#include <unistd.h>
#include <limits.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <stdarg.h>
#import <Foundation/Foundation.h>

// Original functions
static char *(*orig_getenv)(const char *) = NULL;
static int (*orig_open)(const char *, int, ...);
static int (*orig_stat)(const char *, struct stat *);
static int (*orig_access)(const char *, int);

static const char *get_container_path() {
    const char *cont = getenv("IX_CONTAINER");
    if (!cont) return NULL;
    static __thread char buf[PATH_MAX];
    snprintf(buf, sizeof(buf), "/var/mobile/InstanceX/containers/%s", cont);
    return buf;
}

static const char *redirect_path(const char *path) {
    if (!path) return path;
    const char *container = get_container_path();
    if (!container) return path;

    // We only redirect paths that are in /var/mobile
    if (strncmp(path, "/var/mobile", 11) == 0) {
        // Avoid redirecting InstanceX's own container path to prevent recursion
        if (strncmp(path, "/var/mobile/InstanceX", 21) == 0) return path;

        // Avoid system paths that should be shared
        if (strstr(path, "/Library/Caches/com.apple.") || strstr(path, "/Library/Preferences/com.apple.")) return path;
        if (strstr(path, "/Library/Preferences/.GlobalPreferences.plist")) return path;

        static __thread char redirected[PATH_MAX];
        snprintf(redirected, sizeof(redirected), "%s%s", container, path + 11);
        return redirected;
    }
    return path;
}

// Hooks

// NSHomeDirectory must return NSString *
NSString *IX_NSHomeDirectory(void) {
    const char *container = get_container_path();
    if (container) return [NSString stringWithUTF8String:container];

    static NSString *(*orig_NSHomeDirectory)(void) = NULL;
    if (!orig_NSHomeDirectory) orig_NSHomeDirectory = (NSString *(*)(void))dlsym(RTLD_NEXT, "NSHomeDirectory");

    if (orig_NSHomeDirectory) return orig_NSHomeDirectory();
    return @"/var/mobile";
}

// Redefine NSHomeDirectory via dyld interposing or just replacement if using Logos,
// but here we are in a dylib that will be loaded via DYLD_INSERT_LIBRARIES.
// Standard C hook works for C functions, for ObjC/Foundation we might need more.
// For now, let's keep it as a replacement symbol that dyld should prefer.

char *getenv(const char *name) {
    if (!orig_getenv) orig_getenv = dlsym(RTLD_NEXT, "getenv");
    if (name && strcmp(name, "HOME") == 0) {
        const char *container = get_container_path();
        if (container) return (char *)container;
    }
    return orig_getenv(name);
}

int open(const char *path, int oflag, ...) {
    if (!orig_open) orig_open = dlsym(RTLD_NEXT, "open");
    mode_t mode = 0;
    if (oflag & O_CREAT) {
        va_list ap;
        va_start(ap, oflag);
        mode = (mode_t)va_arg(ap, int);
        va_end(ap);
    }
    return orig_open(redirect_path(path), oflag, mode);
}

int stat(const char *path, struct stat *buf) {
    if (!orig_stat) orig_stat = dlsym(RTLD_NEXT, "stat");
    return orig_stat(redirect_path(path), buf);
}

int access(const char *path, int amode) {
    if (!orig_access) orig_access = dlsym(RTLD_NEXT, "access");
    return orig_access(redirect_path(path), amode);
}

// Restore SHM hooks
static int should_prefix_shm(const char *name) {
    if (!name || name[0] == '\0') return 0;
    if (name[0] != '/') return 0;
    if (strncmp(name, "/com.apple.", 11) == 0) return 0;
    if (strncmp(name, "/Apple", 6) == 0 || strncmp(name, "/apple", 6) == 0) return 0;
    return 1;
}

static const char *prefixed_shm_name(const char *name) {
    const char *ns = getenv("IX_SHM_NAMESPACE");
    if (!ns || !should_prefix_shm(name)) return name;
    size_t nsLen = strlen(ns);
    size_t nameLen = strlen(name);
    static __thread char buf[PATH_MAX];
    if (nsLen + nameLen + 1 >= sizeof(buf)) return name;
    if (name[0] == '/') {
        snprintf(buf, sizeof(buf), "/%s%s", ns, name);
    } else {
        snprintf(buf, sizeof(buf), "/%s/%s", ns, name);
    }
    return buf;
}

int shm_open(const char *name, int oflag, ...) {
    static int (*orig_shm_open)(const char *, int, mode_t) = NULL;
    if (!orig_shm_open) orig_shm_open = dlsym(RTLD_NEXT, "shm_open");
    mode_t mode = 0;
    if (oflag & O_CREAT) {
        va_list ap;
        va_start(ap, oflag);
        mode = (mode_t)va_arg(ap, int);
        va_end(ap);
    }
    const char *prefixed = prefixed_shm_name(name);
    return orig_shm_open(prefixed, oflag, mode);
}

int shm_unlink(const char *name) {
    static int (*orig_shm_unlink)(const char *) = NULL;
    if (!orig_shm_unlink) orig_shm_unlink = dlsym(RTLD_NEXT, "shm_unlink");
    const char *prefixed = prefixed_shm_name(name);
    return orig_shm_unlink(prefixed);
}

// Dyld interposing
typedef struct interpose_substitution {
    const void* replacement;
    const void* original;
} interpose_substitution_t;

#define DYLD_INTERPOSE(_replacement,_original) \
    __attribute__((used)) static const interpose_substitution_t interpose_##_original \
    __attribute__ ((section ("__DATA, __interpose"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_original };

DYLD_INTERPOSE(IX_NSHomeDirectory, NSHomeDirectory)
DYLD_INTERPOSE(getenv, getenv)
DYLD_INTERPOSE(open, open)
DYLD_INTERPOSE(stat, stat)
DYLD_INTERPOSE(access, access)
DYLD_INTERPOSE(shm_open, shm_open)
DYLD_INTERPOSE(shm_unlink, shm_unlink)
