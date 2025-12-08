// ContainerShim.c
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

typedef char *(*orig_NSHomeDirectory_t)(void);
static orig_NSHomeDirectory_t orig_NSHomeDirectory = NULL;

static char *make_container_home() {
    const char *cont = getenv("IX_CONTAINER");
    if (!cont) return NULL;
    static char buf[PATH_MAX];
    snprintf(buf, sizeof(buf), "/var/mobile/InstanceX/containers/%s", cont);
    return buf;
}

char *NSHomeDirectory(void) {
    if (!orig_NSHomeDirectory) {
        orig_NSHomeDirectory = (orig_NSHomeDirectory_t)dlsym(RTLD_NEXT, "NSHomeDirectory");
    }
    char *container = make_container_home();
    if (container) {
        return strdup(container);
    }
    if (orig_NSHomeDirectory) return orig_NSHomeDirectory();
    return strdup("/var/mobile");
}

char *getenv(const char *name) {
    static char *(*orig_getenv)(const char *) = NULL;
    if (!orig_getenv) orig_getenv = (char *(*)(const char *))dlsym(RTLD_NEXT, "getenv");
    if (!name) return orig_getenv(name);
    if (strcmp(name, "HOME") == 0) {
        char *container = make_container_home();
        if (container) return strdup(container);
    }
    return orig_getenv(name);
}

int getpwuid_r(uid_t uid, struct passwd *pwd, char *buf, size_t buflen, struct passwd **result) {
    static int (*orig_getpwuid_r)(uid_t, struct passwd*, char*, size_t, struct passwd**) = NULL;
    if (!orig_getpwuid_r) orig_getpwuid_r = dlsym(RTLD_NEXT, "getpwuid_r");
    int ret = orig_getpwuid_r(uid, pwd, buf, buflen, result);
    if (ret == 0 && result && *result) {
        const char *cont = getenv("IX_CONTAINER");
        if (cont) {
            static char pathbuf[PATH_MAX];
            snprintf(pathbuf, sizeof(pathbuf), "/var/mobile/InstanceX/containers/%s", cont);
            (*result)->pw_dir = pathbuf;
        }
    }
    return ret;
}

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
