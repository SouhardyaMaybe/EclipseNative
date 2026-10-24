/*
 * Runtime compatibility shims for API 26.
 *
 * Both functions are compiled into their consumer and hidden by the version
 * script; they are not part of the public surface.
 */
#include "android_compat.h"

#include <errno.h>

void *eclipse_aligned_alloc(size_t alignment, size_t size) {
    void *pointer = NULL;
    int error = posix_memalign(&pointer, alignment, size);
    if (error != 0) {
        errno = error;
        return NULL;
    }
    return pointer;
}

int eclipse_memfd_create(const char *name, unsigned int flags) {
#ifdef __NR_memfd_create
    return (int)syscall(__NR_memfd_create, name, flags);
#else
    (void)name;
    (void)flags;
    errno = ENOSYS;
    return -1;
#endif
}
