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
#include <dirent.h>
#include <sys/time.h>
#import <Foundation/Foundation.h>

// Original functions
static int (*orig_open)(const char *, int, ...);
static int (*orig_stat)(const char *, struct stat *);
static int (*orig_lstat)(const char *, struct stat *);
static int (*orig_access)(const char *, int);
static int (*orig_rename)(const char *, const char *);
static int (*orig_unlink)(const char *);
static int (*orig_mkdir)(const char *, mode_t);
static int (*orig_rmdir)(const char *);
static int (*orig_chmod)(const char *, mode_t);
static int (*orig_chown)(const char *, uid_t, gid_t);
static ssize_t (*orig_readlink)(const char *, char *, size_t);
static int (*orig_symlink)(const char *, const char *);
static int (*orig_link)(const char *, const char *);
static int (*orig_utimes)(const char *, const struct timeval *);
static DIR* (*orig_opendir)(const char *);
static int (*orig_remove)(const char *);

static const char *get_container_path() {
    const char *cont = getenv("IX_CONTAINER");
    if (!cont) return NULL;
    static __thread char buf[PATH_MAX];
    snprintf(buf, sizeof(buf), "/var/mobile/InstanceX/containers/%s", cont);
    return buf;
}

// Fixed redirect_path with multi-buffer support to avoid overwriting in functions like rename()
static const char *redirect_path(const char *path) {
    if (!path) return path;
    const char *container = get_container_path();
    if (!container) return path;

    if (strncmp(path, "/var/mobile", 11) == 0) {
        if (strncmp(path, "/var/mobile/InstanceX", 21) == 0) return path;
        if (strstr(path, "/Library/Caches/com.apple.") || strstr(path, "/Library/Preferences/com.apple.")) return path;
        if (strstr(path, "/Library/Preferences/.GlobalPreferences.plist")) return path;

        static __thread char redirected[4][PATH_MAX];
        static __thread int buf_idx = 0;
        buf_idx = (buf_idx + 1) % 4;
        snprintf(redirected[buf_idx], PATH_MAX, "%s%s", container, path + 11);
        return redirected[buf_idx];
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

int IX_lstat(const char *path, struct stat *buf) {
    if (!orig_lstat) orig_lstat = dlsym(RTLD_NEXT, "lstat");
    return orig_lstat(redirect_path(path), buf);
}

int IX_access(const char *path, int amode) {
    if (!orig_access) orig_access = dlsym(RTLD_NEXT, "access");
    return orig_access(redirect_path(path), amode);
}

int IX_rename(const char *old, const char *newp) {
    if (!orig_rename) orig_rename = dlsym(RTLD_NEXT, "rename");
    const char *r_old = strdup(redirect_path(old));
    int ret = orig_rename(r_old, redirect_path(newp));
    free((void*)r_old);
    return ret;
}

int IX_unlink(const char *path) {
    if (!orig_unlink) orig_unlink = dlsym(RTLD_NEXT, "unlink");
    return orig_unlink(redirect_path(path));
}

int IX_mkdir(const char *path, mode_t mode) {
    if (!orig_mkdir) orig_mkdir = dlsym(RTLD_NEXT, "mkdir");
    return orig_mkdir(redirect_path(path), mode);
}

int IX_rmdir(const char *path) {
    if (!orig_rmdir) orig_rmdir = dlsym(RTLD_NEXT, "rmdir");
    return orig_rmdir(redirect_path(path));
}

int IX_chmod(const char *path, mode_t mode) {
    if (!orig_chmod) orig_chmod = dlsym(RTLD_NEXT, "chmod");
    return orig_chmod(redirect_path(path), mode);
}

int IX_chown(const char *path, uid_t owner, gid_t group) {
    if (!orig_chown) orig_chown = dlsym(RTLD_NEXT, "chown");
    return orig_chown(redirect_path(path), owner, group);
}

ssize_t IX_readlink(const char *path, char *buf, size_t bufsiz) {
    if (!orig_readlink) orig_readlink = dlsym(RTLD_NEXT, "readlink");
    return orig_readlink(redirect_path(path), buf, bufsiz);
}

int IX_symlink(const char *path1, const char *path2) {
    if (!orig_symlink) orig_symlink = dlsym(RTLD_NEXT, "symlink");
    const char *r_path1 = strdup(redirect_path(path1));
    int ret = orig_symlink(r_path1, redirect_path(path2));
    free((void*)r_path1);
    return ret;
}

int IX_link(const char *path1, const char *path2) {
    if (!orig_link) orig_link = dlsym(RTLD_NEXT, "link");
    const char *r_path1 = strdup(redirect_path(path1));
    int ret = orig_link(r_path1, redirect_path(path2));
    free((void*)r_path1);
    return ret;
}

int IX_utimes(const char *path, const struct timeval times[2]) {
    if (!orig_utimes) orig_utimes = dlsym(RTLD_NEXT, "utimes");
    return orig_utimes(redirect_path(path), times);
}

DIR* IX_opendir(const char *path) {
    if (!orig_opendir) orig_opendir = dlsym(RTLD_NEXT, "opendir");
    return orig_opendir(redirect_path(path));
}

int IX_remove(const char *path) {
    if (!orig_remove) orig_remove = dlsym(RTLD_NEXT, "remove");
    return orig_remove(redirect_path(path));
}

// CFPreferences hooks for NSUserDefaults isolation
static CFPropertyListRef (*orig_CFPreferencesCopyAppValue)(CFStringRef, CFStringRef);
static void (*orig_CFPreferencesSetAppValue)(CFStringRef, CFPropertyListRef, CFStringRef);

CFPropertyListRef IX_CFPreferencesCopyAppValue(CFStringRef key, CFStringRef applicationID) {
    if (!orig_CFPreferencesCopyAppValue) orig_CFPreferencesCopyAppValue = dlsym(RTLD_NEXT, "CFPreferencesCopyAppValue");
    const char *cont = getenv("IX_CONTAINER");
    if (cont && applicationID) {
        NSString *newAppID = [NSString stringWithFormat:@"%s.%@", cont, (__bridge NSString *)applicationID];
        return orig_CFPreferencesCopyAppValue(key, (__bridge CFStringRef)newAppID);
    }
    return orig_CFPreferencesCopyAppValue(key, applicationID);
}

void IX_CFPreferencesSetAppValue(CFStringRef key, CFPropertyListRef value, CFStringRef applicationID) {
    if (!orig_CFPreferencesSetAppValue) orig_CFPreferencesSetAppValue = dlsym(RTLD_NEXT, "CFPreferencesSetAppValue");
    const char *cont = getenv("IX_CONTAINER");
    if (cont && applicationID) {
        NSString *newAppID = [NSString stringWithFormat:@"%s.%@", cont, (__bridge NSString *)applicationID];
        orig_CFPreferencesSetAppValue(key, value, (__bridge CFStringRef)newAppID);
        return;
    }
    orig_CFPreferencesSetAppValue(key, value, applicationID);
}

// IPC Isolation (SHM)
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
    static __thread char buf[PATH_MAX];
    if (name[0] == '/') {
        snprintf(buf, sizeof(buf), "/%s%s", ns, name);
    } else {
        snprintf(buf, sizeof(buf), "/%s/%s", ns, name);
    }
    return buf;
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
    return orig_shm_open(prefixed_shm_name(name), oflag, mode);
}

int IX_shm_unlink(const char *name) {
    static int (*orig_shm_unlink)(const char *) = NULL;
    if (!orig_shm_unlink) orig_shm_unlink = dlsym(RTLD_NEXT, "shm_unlink");
    return orig_shm_unlink(prefixed_shm_name(name));
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
DYLD_INTERPOSE(IX_lstat, lstat)
DYLD_INTERPOSE(IX_access, access)
DYLD_INTERPOSE(IX_rename, rename)
DYLD_INTERPOSE(IX_unlink, unlink)
DYLD_INTERPOSE(IX_mkdir, mkdir)
DYLD_INTERPOSE(IX_rmdir, rmdir)
DYLD_INTERPOSE(IX_chmod, chmod)
DYLD_INTERPOSE(IX_chown, chown)
DYLD_INTERPOSE(IX_readlink, readlink)
DYLD_INTERPOSE(IX_symlink, symlink)
DYLD_INTERPOSE(IX_link, link)
DYLD_INTERPOSE(IX_utimes, utimes)
DYLD_INTERPOSE(IX_opendir, opendir)
DYLD_INTERPOSE(IX_remove, remove)
DYLD_INTERPOSE(IX_CFPreferencesCopyAppValue, CFPreferencesCopyAppValue)
DYLD_INTERPOSE(IX_CFPreferencesSetAppValue, CFPreferencesSetAppValue)
DYLD_INTERPOSE(IX_shm_open, shm_open)
DYLD_INTERPOSE(IX_shm_unlink, shm_unlink)
