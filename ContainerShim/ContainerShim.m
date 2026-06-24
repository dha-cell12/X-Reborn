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

    if (strncmp(path, "/var/mobile", 11) == 0) {
        if (strncmp(path, "/var/mobile/InstanceX", 21) == 0) return path;
        if (strstr(path, "/Library/Caches/com.apple.") || strstr(path, "/Library/Preferences/com.apple.")) return path;
        if (strstr(path, "/Library/Preferences/.GlobalPreferences.plist")) return path;

        static __thread char redirected[PATH_MAX];
        snprintf(redirected, sizeof(redirected), "%s%s", container, path + 11);
        return redirected;
    }
    return path;
}

// Replacement functions
NSString *IX_NSHomeDirectory(void) {
    const char *container = get_container_path();
    if (container) return [NSString stringWithUTF8String:container];
    static NSString *(*orig_NSHomeDirectory)(void) = NULL;
    if (!orig_NSHomeDirectory) orig_NSHomeDirectory = (NSString *(*)(void))dlsym(RTLD_NEXT, "NSHomeDirectory");
    return orig_NSHomeDirectory ? orig_NSHomeDirectory() : @"/var/mobile";
}

char *IX_getenv(const char *name) {
    static char *(*orig_getenv)(const char *) = NULL;
    if (!orig_getenv) orig_getenv = dlsym(RTLD_NEXT, "getenv");
    if (name && strcmp(name, "HOME") == 0) {
        const char *container = get_container_path();
        if (container) return (char *)container;
    }
    return orig_getenv(name);
}

int IX_open(const char *path, int oflag, ...) {
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

int IX_stat(const char *path, struct stat *buf) {
    if (!orig_stat) orig_stat = dlsym(RTLD_NEXT, "stat");
    return orig_stat(redirect_path(path), buf);
}

int IX_access(const char *path, int amode) {
    if (!orig_access) orig_access = dlsym(RTLD_NEXT, "access");
    return orig_access(redirect_path(path), amode);
}

int IX_shm_open(const char *name, int oflag, ...) {
    static int (*orig_shm_open)(const char *, int, mode_t) = NULL;
    if (!orig_shm_open) orig_shm_open = dlsym(RTLD_NEXT, "shm_open");
    mode_t mode = 0;
    if (oflag & O_CREAT) {
        va_list ap;
        va_start(ap, oflag);
        mode = (mode_t)va_arg(ap, int);
        va_end(ap);
    }
    // Namespace logic handled in previous versions if needed
    return orig_shm_open(name, oflag, mode);
}

int IX_shm_unlink(const char *name) {
    static int (*orig_shm_unlink)(const char *) = NULL;
    if (!orig_shm_unlink) orig_shm_unlink = dlsym(RTLD_NEXT, "shm_unlink");
    return orig_shm_unlink(name);
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
DYLD_INTERPOSE(IX_getenv, getenv)
DYLD_INTERPOSE(IX_open, open)
DYLD_INTERPOSE(IX_stat, stat)
DYLD_INTERPOSE(IX_access, access)
DYLD_INTERPOSE(IX_shm_open, shm_open)
DYLD_INTERPOSE(IX_shm_unlink, shm_unlink)
