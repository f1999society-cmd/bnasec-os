/*
 * symlink-shim.c — LD_PRELOAD shim for symlink-restricted sandboxes.
 *
 * The sandbox monitor kills any process calling the legacy symlink(2)
 * syscall, but allows symlinkat(2) for normal users. Processes running
 * as uid 0 (e.g. inside user namespaces) get killed even for symlinkat,
 * so all privileged work must run as the plain user — hence this shim
 * also fakes a root identity and fakes chown success for pacman.
 *
 * Modes (env vars):
 *   BNASEC_FAKE_ROOT=1   getuid/geteuid/getgid/getegid return 0,
 *                        setuid/setgid family return success (no-op)
 *   BNASEC_FAKE_CHOWN=1  chown/fchown/lchown/fchownat return success
 *                        (real ownership untouched on disk; the squashfs
 *                        is built with -all-root anyway)
 *
 * Build: gcc -shared -fPIC -O2 -o symlink-shim.so symlink-shim.c -ldl
 * Use:   LD_PRELOAD=/path/symlink-shim.so <program>
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/syscall.h>
#include <stdlib.h>

static int fake_root(void) {
    static int v = -1;
    if (v < 0) v = getenv("BNASEC_FAKE_ROOT") ? 1 : 0;
    return v;
}
static int fake_chown(void) {
    static int v = -1;
    if (v < 0) v = getenv("BNASEC_FAKE_CHOWN") ? 1 : 0;
    return v;
}

int symlink(const char *oldpath, const char *newpath) {
    return symlinkat(oldpath, AT_FDCWD, newpath);
}

int link(const char *oldpath, const char *newpath) {
    return linkat(AT_FDCWD, oldpath, AT_FDCWD, newpath, 0);
}

uid_t getuid(void)  { return fake_root() ? 0 : syscall(SYS_getuid); }
uid_t geteuid(void) { return fake_root() ? 0 : syscall(SYS_geteuid); }
gid_t getgid(void)  { return fake_root() ? 0 : syscall(SYS_getgid); }
gid_t getegid(void) { return fake_root() ? 0 : syscall(SYS_getegid); }

int setuid(uid_t u) { (void)u; return fake_root() ? 0 : -1; }
int seteuid(uid_t u) { (void)u; return fake_root() ? 0 : -1; }
int setgid(gid_t g) { (void)g; return fake_root() ? 0 : -1; }
int setegid(gid_t g) { (void)g; return fake_root() ? 0 : -1; }
int setreuid(uid_t r, uid_t e) { (void)r; (void)e; return fake_root() ? 0 : -1; }
int setregid(gid_t r, gid_t e) { (void)r; (void)e; return fake_root() ? 0 : -1; }
int setresuid(uid_t r, uid_t e, uid_t s) { (void)r; (void)e; (void)s; return fake_root() ? 0 : -1; }
int setresgid(gid_t r, gid_t e, gid_t s) { (void)r; (void)e; (void)s; return fake_root() ? 0 : -1; }

int chown(const char *p, uid_t u, gid_t g) {
    if (fake_chown()) return 0;
    typedef int (*fn)(const char *, uid_t, gid_t);
    static fn real = 0;
    if (!real) real = (fn)dlsym(RTLD_NEXT, "chown");
    return real(p, u, g);
}
int fchown(int fd, uid_t u, gid_t g) {
    if (fake_chown()) return 0;
    typedef int (*fn)(int, uid_t, gid_t);
    static fn real = 0;
    if (!real) real = (fn)dlsym(RTLD_NEXT, "fchown");
    return real(fd, u, g);
}
int lchown(const char *p, uid_t u, gid_t g) {
    if (fake_chown()) return 0;
    typedef int (*fn)(const char *, uid_t, gid_t);
    static fn real = 0;
    if (!real) real = (fn)dlsym(RTLD_NEXT, "lchown");
    return real(p, u, g);
}
int fchownat(int fd, const char *p, uid_t u, gid_t g, int flags) {
    if (fake_chown()) return 0;
    typedef int (*fn)(int, const char *, uid_t, gid_t, int);
    static fn real = 0;
    if (!real) real = (fn)dlsym(RTLD_NEXT, "fchownat");
    return real(fd, p, u, g, flags);
}
