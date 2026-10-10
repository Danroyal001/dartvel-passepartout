// SPDX-License-Identifier: GPL-3.0
// Copy borrowed native strings before asynchronous Dart listeners receive them.
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <dlfcn.h>
#include <dirent.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <linux/if_tun.h>
#include "partout.h"
static void (*emit)(int, char *, uint64_t, uint64_t);
static int (*start_fn)(const partout_daemon_start_args *);
static void (*stop_fn)(void);
static char *profile;
static void emit_event(int kind, const char *s, uint64_t a, uint64_t b) {
    char *copy = s ? strdup(s) : NULL;
    if (s && !copy) return;
    emit(kind, copy, a, b); // Dart owns copy and frees it after delivery.
}
static void status(void *ctx, const char *s) { (void)ctx; emit_event(0,s,0,0); }
static void count(void *ctx, uint64_t a, uint64_t b) { (void)ctx; emit_event(1,NULL,a,b); }
static void error(void *ctx, const char *s) { (void)ctx; emit_event(2,s,0,0); }
static void logger(void *ctx, int level, const char *s) { (void)ctx; emit_event(3,s,level,0); }
static void *run(void *unused) {
    (void)unused;
    partout_daemon_bindings bindings = { .events = {
        .set_connection_status=status, .set_data_count=count, .set_last_error_code=error
    }};
    partout_daemon_start_args args = { .profile=profile,
        .options={.is_daemon=true, .starts_immediately=true, .cancels_unrecoverable=true},
        .bindings=&bindings };
    int code=start_fn(&args);
    free(profile); profile=NULL;
    emit_event(4,NULL,(uint64_t)(int64_t)code,0);
    return NULL;
}
int tunnel_start(const char *library, const char *json,
                 void (*listener)(int,char *,uint64_t,uint64_t)) {
    emit=listener;
    void *lib=dlopen(library,RTLD_NOW|RTLD_GLOBAL);
    if (!lib) { emit_event(3,dlerror(),0,0); return -1; }
    void (*init)(const partout_init_args *)=dlsym(lib,"partout_init");
    start_fn=dlsym(lib,"partout_daemon_start"); stop_fn=dlsym(lib,"partout_daemon_stop");
    if (!init || !start_fn || !stop_fn) return -1;
    partout_init_args args={.logs_private_data=false,.logger_fn=logger}; init(&args);
    profile=strdup(json); if (!profile) return -3;
    pthread_t thread;
    if (pthread_create(&thread,NULL,run,NULL)) { free(profile); profile=NULL; return -1; }
    pthread_detach(thread); return 0;
}
void tunnel_stop(void) { if(stop_fn) stop_fn(); }
void tunnel_free(void *p) { free(p); }
// The name of the tun device the engine opened in this process, so the
// helper can configure it. Scans /proc/self/fd for /dev/net/tun and asks the
// kernel with TUNGETIFF. Returns 1 and fills out (IFNAMSIZ bytes) when found.
int tunnel_device_name(char *out, int out_len) {
    if (!out || out_len < IFNAMSIZ) return 0;
    DIR *dir = opendir("/proc/self/fd");
    if (!dir) return 0;
    int found = 0;
    struct dirent *entry;
    while ((entry = readdir(dir))) {
        char path[64], target[64];
        int fd = atoi(entry->d_name);
        if (entry->d_name[0] == '.' || fd == dirfd(dir)) continue;
        snprintf(path, sizeof(path), "/proc/self/fd/%d", fd);
        ssize_t len = readlink(path, target, sizeof(target) - 1);
        if (len <= 0) continue;
        target[len] = 0;
        if (strcmp(target, "/dev/net/tun") != 0) continue;
        struct ifreq ifr;
        memset(&ifr, 0, sizeof(ifr));
        if (ioctl(fd, TUNGETIFF, &ifr) == 0 && ifr.ifr_name[0]) {
            memcpy(out, ifr.ifr_name, IFNAMSIZ);
            out[IFNAMSIZ - 1] = 0;
            found = 1; // keep scanning: the newest device has the highest fd
        }
    }
    closedir(dir);
    return found;
}
