/*
 * EclipseNatives compatibility header.
 *
 * Force-included (-include) while compiling upstream sources and libraries.
 * It exists because the app supports API 26, while two libc entry points used
 * by those sources were added later:
 *
 *   - memfd_create   API 30 (libffi's closure allocator)
 *   - aligned_alloc  API 28 (LWJGL's libc bindings and allocator setup)
 *
 * The implementations live in android_compat.c and use the same kernel
 * interfaces the platform would, so behaviour is not approximated.
 *
 * The redirection macros are opt-in per translation unit. They are deliberately
 * not defined globally: LWJGL's lwjgl_malloc.h uses "aligned_alloc" as a JNI
 * parameter name in SETUP_MALLOC, and rewriting it everywhere would make the
 * generated code harder to compare with upstream. Parameter names are not part
 * of the JNI contract, but a narrow opt-in keeps the audit simple.
 */
#pragma once

/* Include the system headers first: their guards then keep a later include
 * from re-declaring the redirected names with an availability attribute. */
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <sys/syscall.h>

/* LWJGL bundles a liburing shim whose compat.h predates the Linux 5.x UAPI
 * and assumes <linux/time_types.h> is unavailable. NDK r28 ships the UAPI
 * headers, so including both redefines struct __kernel_timespec. Skip the
 * shim and take the definitions from the sysroot instead. The only shim
 * definition the UAPI lacks is BLOCK_URING_CMD_DISCARD. */
#if defined(__ANDROID__)
#define LIBURING_COMPAT_H 1
#include <linux/types.h>
#include <linux/ioctl.h>
#include <linux/openat2.h>
#include <linux/time_types.h>
#ifndef BLOCK_URING_CMD_DISCARD
#define BLOCK_URING_CMD_DISCARD _IO(0x12, 0)
#endif
#endif

#ifdef __cplusplus
extern "C" {
#endif

void *eclipse_aligned_alloc(size_t alignment, size_t size);
int eclipse_memfd_create(const char *name, unsigned int flags);

#ifdef __cplusplus
}
#endif

#ifndef MFD_CLOEXEC
#define MFD_CLOEXEC 0x0001U
#endif

#if defined(ECLIPSE_COMPAT_REDIRECT_ALLOC) && defined(__ANDROID__) && (__ANDROID_API__ < 28)
#define aligned_alloc eclipse_aligned_alloc
#endif

#if defined(ECLIPSE_COMPAT_REDIRECT_MEMFD) && defined(__ANDROID__) && (__ANDROID_API__ < 30)
#define memfd_create eclipse_memfd_create
#endif
